//! Puts the Veneratoh Client branding back into the PolyPlus mod right before launch.
//!
//! The mod is downloaded from upstream and checked against its hash, so the pristine copy
//! stays in the download cache and only the jar inside the game folders gets patched.
//! Best effort: a failure here is logged and the game launches anyway.

include!("veneratoh_patch_files.rs");

pub async fn apply(clusters: &std::path::Path, shared: &std::path::Path) {
    #[cfg(windows)]
    {
        run(clusters, shared).await;
    }

    #[cfg(not(windows))]
    {
        let _ = (clusters, shared);
    }
}

#[cfg(windows)]
async fn run(clusters: &std::path::Path, shared: &std::path::Path) {
    let dir = std::env::temp_dir().join("veneratoh-patch");
    if let Err(err) = tokio::fs::create_dir_all(&dir).await {
        tracing::warn!(error = %err, "veneratoh patch: could not create the temp folder");
        return;
    }

    for &(name, bytes) in PATCH_FILES {
        if let Err(err) = tokio::fs::write(dir.join(name), bytes).await {
            tracing::warn!(file = name, error = %err, "veneratoh patch: could not write a file");
            return;
        }
    }

    let mut command = tokio::process::Command::new("powershell");
    command
        .arg("-NoProfile")
        .arg("-NonInteractive")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(dir.join("apply.ps1"))
        .arg("-Clusters")
        .arg(clusters)
        .arg("-Shared")
        .arg(shared)
        .kill_on_drop(true)
        .creation_flags(0x0800_0000);

    match tokio::time::timeout(std::time::Duration::from_secs(180), command.output()).await {
        Ok(Ok(output)) => {
            if output.status.success() {
                tracing::debug!(
                    output = %String::from_utf8_lossy(&output.stdout),
                    "veneratoh patch applied"
                );
                let stderr = String::from_utf8_lossy(&output.stderr);
                if !stderr.trim().is_empty() {
                    tracing::warn!(stderr = %stderr, "veneratoh patch reported problems");
                }
            } else {
                tracing::warn!(
                    stderr = %String::from_utf8_lossy(&output.stderr),
                    "veneratoh patch failed"
                );
            }
        }
        Ok(Err(err)) => tracing::warn!(error = %err, "veneratoh patch: could not start powershell"),
        Err(_) => tracing::warn!("veneratoh patch: timed out"),
    }
}
