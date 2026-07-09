use std::process::Command;

// Embeds the current git commit as `env!("GIT_COMMIT")`. Written to receipts.parser_commit
// so the dev ingest harness can detect when parser code changed and re-parse.
fn main() {
    let commit = Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string());

    println!("cargo:rustc-env=GIT_COMMIT={commit}");

    // The crate lives in backend/, so .git is one directory up. Only emit
    // rerun-if-changed for paths that exist (avoids churn when .git is absent).
    for p in ["../.git/HEAD", "../.git/refs/heads", "../.git/packed-refs"] {
        if std::path::Path::new(p).exists() {
            println!("cargo:rerun-if-changed={p}");
        }
    }
}
