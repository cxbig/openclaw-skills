use anyhow::{Context, Result};
use clap::Parser;
use owo_colors::OwoColorize;
use rayon::prelude::*;
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};
use walkdir::WalkDir;

#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Args {
    /// Root directory to search for git repositories.
    ///
    /// This is a required positional argument.
    #[arg(value_name = "ROOT_DIR")]
    root_dir: PathBuf,

    /// Print additional debug information: branch details per repo and NOK error blocks.
    #[arg(long)]
    debug: bool,

    /// Max parallel workers.
    #[arg(long, default_value_t = 20)]
    batch: usize,
}

#[derive(Debug, Clone)]
struct RepoJob {
    root: PathBuf,
    project_full_path: String,
}

#[derive(Debug, Clone)]
struct SkipJob {
    project_full_path: String,
}

enum JobResult {
    Ok,
    Nok,
}

fn main() -> Result<()> {
    let args = Args::parse();

    let root_dir = args.root_dir.clone();

    // Configure rayon thread pool.
    rayon::ThreadPoolBuilder::new()
        .num_threads(args.batch)
        .build_global()
        .ok();

    let started = Instant::now();

    let (repos, skipped) = discover_repos(&root_dir)?;

    let total = repos.len() + skipped.len();
    let ok = AtomicUsize::new(0);
    let nok = AtomicUsize::new(0);
    let skip_n = skipped.len();

    // Print skipped repos in deterministic order before parallel processing.
    for s in &skipped {
        print_skip(&s.project_full_path);
    }

    repos.par_iter().for_each(|repo| {
        match refresh_one(repo, &args) {
            Ok(JobResult::Ok) => {
                ok.fetch_add(1, Ordering::Relaxed);
            }
            Ok(JobResult::Nok) => {
                nok.fetch_add(1, Ordering::Relaxed);
            }
            Err(err) => {
                // Safety net for spawn failures; refresh_one normally handles NOK itself.
                let msg = format!("unexpected error: {:#}", err);
                print_nok(&repo.project_full_path, &msg, None, args.debug);
                nok.fetch_add(1, Ordering::Relaxed);
            }
        }
    });

    let elapsed = started.elapsed();
    let ok_n = ok.load(Ordering::Relaxed);
    let nok_n = nok.load(Ordering::Relaxed);

    println!(
        "{}",
        format!(
            "Processed {} projects: OK {}, NOK {}, SKIP {}. Total time {}.",
            total,
            ok_n,
            nok_n,
            skip_n,
            fmt_duration(elapsed)
        )
        .green()
    );

    Ok(())
}

fn discover_repos(root: &Path) -> Result<(Vec<RepoJob>, Vec<SkipJob>)> {
    let mut repos = Vec::new();
    let mut skipped = Vec::new();

    // Find .git directories; treat their parent as repo root.
    // Do not descend into .git directories.
    let walker = WalkDir::new(root).follow_links(false).into_iter();

    for entry in walker {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };

        let path = entry.path();

        if entry.file_type().is_dir() && entry.file_name() == OsStr::new(".git") {
            let repo_root = match path.parent() {
                Some(p) => p.to_path_buf(),
                None => continue,
            };

            // Skip common junk directories (virtualenvs, IDE metadata, dependencies).
            if repo_root
                .components()
                .any(|c| matches!(c.as_os_str().to_str(), Some(".venv" | "node_modules" | ".idea")))
            {
                continue;
            }

            let project_full_path = gitlab_project_full_path(&repo_root)
                .unwrap_or_else(|| fallback_display_path(root, &repo_root));

            // Ignore marker: record as skipped instead of silently dropping.
            if repo_root.join(".ignore").exists() {
                skipped.push(SkipJob { project_full_path });
                continue;
            }

            repos.push(RepoJob {
                root: repo_root,
                project_full_path,
            });
        }
    }

    // De-dup by path in case nested walk finds duplicates.
    repos.sort_by(|a, b| a.root.cmp(&b.root));
    repos.dedup_by(|a, b| a.root == b.root);

    skipped.sort_by(|a, b| a.project_full_path.cmp(&b.project_full_path));

    Ok((repos, skipped))
}

fn refresh_one(repo: &RepoJob, args: &Args) -> Result<JobResult> {
    // Determine default branch (best effort).
    // If not detectable, fall back to "main".
    let branch = detect_default_branch(&repo.root).unwrap_or_else(|| "main".to_string());
    let current_branch = git_current_branch(&repo.root);

    let debug_suffix = if args.debug {
        Some(format!("current={:?} default={}", current_branch, branch))
    } else {
        None
    };

    let output = if current_branch.as_deref() == Some(branch.as_str()) {
        // When the default branch is checked out, update it via ff-only pull.
        // This avoids: "refusing to fetch into branch ... checked out".
        let mut cmd = Command::new("git");
        cmd.current_dir(&repo.root)
            .arg("pull")
            .arg("--ff-only")
            .arg("-q")
            .arg("origin")
            .arg(&branch);
        cmd.output().context("failed to spawn git pull")?
    } else {
        // When not on default branch, update local default branch refspec without touching worktree.
        let mut cmd = Command::new("git");
        cmd.current_dir(&repo.root)
            .arg("fetch")
            .arg("origin")
            .arg(format!("{b}:{b}", b = branch))
            .arg("--prune");
        cmd.output().context("failed to spawn git fetch")?
    };

    if output.status.success() {
        print_ok(&repo.project_full_path, debug_suffix.as_deref());
        return Ok(JobResult::Ok);
    }

    let mut combined = String::new();
    combined.push_str(&String::from_utf8_lossy(&output.stdout));
    combined.push_str(&String::from_utf8_lossy(&output.stderr));

    print_nok(
        &repo.project_full_path,
        combined.trim(),
        debug_suffix.as_deref(),
        args.debug,
    );

    Ok(JobResult::Nok)
}

fn git_current_branch(repo_root: &Path) -> Option<String> {
    let out = Command::new("git")
        .current_dir(repo_root)
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() || s == "HEAD" {
        return None;
    }
    Some(s)
}

fn detect_default_branch(repo_root: &Path) -> Option<String> {
    // Try: git symbolic-ref --quiet --short refs/remotes/origin/HEAD
    let out = Command::new("git")
        .current_dir(repo_root)
        .args([
            "symbolic-ref",
            "--quiet",
            "--short",
            "refs/remotes/origin/HEAD",
        ])
        .output()
        .ok()?;

    if !out.status.success() {
        return None;
    }

    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    // usually "origin/main"
    s.strip_prefix("origin/").map(|x| x.to_string())
}

fn fmt_duration(d: Duration) -> String {
    // Format: [[h:]m:]s.zzz
    let ms = d.as_millis() as u64;
    let h = ms / 3_600_000;
    let m = (ms % 3_600_000) / 60_000;
    let s = (ms % 60_000) / 1000;
    let zzz = ms % 1000;

    if h > 0 {
        format!("{}:{:02}:{:02}.{:03}", h, m, s, zzz)
    } else if m > 0 {
        format!("{}:{:02}.{:03}", m, s, zzz)
    } else {
        format!("{}.{:03}", s, zzz)
    }
}

fn fallback_display_path(root: &Path, repo_root: &Path) -> String {
    repo_root
        .strip_prefix(root)
        .ok()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| repo_root.to_string_lossy().to_string())
}

fn gitlab_project_full_path(repo_root: &Path) -> Option<String> {
    // We only return the project path (namespace/name), not the remote URL.
    // This avoids leaking tokens if a remote URL contains credentials.
    let out = Command::new("git")
        .current_dir(repo_root)
        .args(["remote", "get-url", "origin"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }

    let mut s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() {
        return None;
    }

    // Strip trailing .git
    if let Some(stripped) = s.strip_suffix(".git") {
        s = stripped.to_string();
    }

    // Common forms:
    // - git@host:group/subgroup/repo
    // - ssh://git@host/group/subgroup/repo
    // - https://host/group/subgroup/repo
    // - https://user:token@host/group/subgroup/repo

    // Handle SCP-like syntax: git@host:namespace/repo
    if let Some(idx) = s.find(':') {
        // Ensure there's an @ before ':' to reduce false positives on http(s)://
        if s[..idx].contains('@') && !s.contains("//") {
            return Some(s[idx + 1..].to_string());
        }
    }

    // Handle URLs with //
    if let Some(idx) = s.find("//") {
        let after_scheme = &s[idx + 2..];
        // Drop credentials if present: user:pass@host
        let host_and_path = match after_scheme.rsplit_once('@') {
            Some((_creds, rest)) => rest,
            None => after_scheme,
        };
        // host_and_path = host/namespace/repo
        if let Some((_host, path)) = host_and_path.split_once('/') {
            return Some(path.to_string());
        }
    }

    None
}

// Prefix layout (4 chars wide, then " | "):
//   "  OK | "   – 2 spaces + OK
//   " NOK | "   – 1 space  + NOK
//   "SKIP | "   – SKIP
// Error-block continuation uses 5 spaces to align under the pipe:
//   "     | "

fn print_ok(project_path: &str, debug: Option<&str>) {
    let mut line = format!("  OK | {}", project_path);
    if let Some(d) = debug {
        line.push_str(" | ");
        line.push_str(d);
    }
    println!("{}", line.green());
}

fn print_nok(project_path: &str, err: &str, debug: Option<&str>, verbose: bool) {
    let mut line = format!(" NOK | {}", project_path);
    if let Some(d) = debug {
        line.push_str(" | ");
        line.push_str(d);
    }
    println!("{}", line.red());

    if verbose {
        // Keep delimiter stable for parsing/readability.
        let delimiter = "----------------------------------------";
        println!("{}", format!("     | {}", delimiter).red());

        let mut lines = err
            .lines()
            .filter(|l| !l.trim().is_empty())
            .take(10)
            .collect::<Vec<_>>();
        if lines.is_empty() {
            lines.push("(no error output)");
        }
        for line in lines {
            println!("{}", format!("     | {}", line).red());
        }

        println!("{}", format!("     | {}", delimiter).red());
    }
}

fn print_skip(project_path: &str) {
    println!("{}", format!("SKIP | {}", project_path).yellow());
}
