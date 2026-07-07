%dw 2.0
/**
 * dwl::jobStatus — builds the public GET /jobs/{jobId} response from a persisted
 * job record.
 *
 * Pure module: the job record is passed in explicitly (no reliance on payload/vars).
 */

// Human-readable message + recommended poll interval keyed by status.
// nextPollSeconds = 0 means terminal — the caller should stop polling.
var statusMeta = {
    PROCESSING:    { message: "Upgrade accepted and queued.",                               nextPollSeconds: 5  },
    ASSESSING:     { message: "Analyzing the repository and computing the change plan.",    nextPollSeconds: 5  },
    COMMITTING:    { message: "Applying transforms and committing changes to a branch.",    nextPollSeconds: 5  },
    COMMITTED:     { message: "Changes committed; opening a pull request.",                 nextPollSeconds: 5  },
    PR_OPEN:       { message: "Pull request is open and ready for review/merge.",           nextPollSeconds: 0  },
    DEPLOYING:     { message: "PR merged; CI/CD is building and deploying.",                nextPollSeconds: 10 },
    DEPLOYED:      { message: "Upgrade deployed successfully.",                             nextPollSeconds: 0  },
    FAILED_ASSESS: { message: "Assessment failed. See error for details.",                  nextPollSeconds: 0  },
    FAILED_COMMIT: { message: "Commit/transform stage failed. See error for details.",      nextPollSeconds: 0  },
    FAILED_CI:     { message: "CI build/tests failed after merge. See error for details.",  nextPollSeconds: 0  },
    FAILED_DEPLOY: { message: "Deployment failed. See error for details.",                  nextPollSeconds: 0  },
    FAILED_INTERRUPTED: { message: "Upgrade was interrupted before completion (runtime restart/crash) and was automatically failed. Re-submit to retry.", nextPollSeconds: 0 }
}

/**
 * Builds the public JobStatus payload from a stored job record.
 * Optional fields (branchName/prUrl/prNumber/completedAt/error) are included only
 * when present, preserving the original response shape exactly.
 */
fun buildJobStatus(rec) = do {
    var meta = statusMeta[rec.status]
               default { message: ("Status: " ++ (rec.status default "UNKNOWN")), nextPollSeconds: 10 }
    ---
    {
        jobId:           rec.jobId,
        status:          rec.status,
        message:         meta.message,
        nextPollSeconds: meta.nextPollSeconds
    }
    ++ (if (rec.branchName  != null) { branchName:  rec.branchName  } else {})
    ++ (if (rec.prUrl       != null) { prUrl:        rec.prUrl       } else {})
    ++ (if (rec.prNumber    != null) { prNumber:     rec.prNumber    } else {})
    ++ (if (rec.completedAt != null) { completedAt:  rec.completedAt } else {})
    ++ (if (rec.error       != null) { error:        rec.error       } else {})
}
