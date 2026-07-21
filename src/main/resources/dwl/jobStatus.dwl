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
    NO_CHANGE:     { message: "No changes required — the target already meets the Java 17 matrix.", nextPollSeconds: 0 },
    MUNIT_FAILED:  { message: "MUnit tests failed in CI. Paused for human action — fix the tests; the job resumes automatically when CI reports a test success.", nextPollSeconds: 300 },
    DEPLOYING:     { message: "PR merged; CI/CD is building and deploying.",                nextPollSeconds: 10 },
    DEPLOYED:      { message: "Upgrade deployed successfully.",                             nextPollSeconds: 0  },
    CLOSED:        { message: "The upgrade pull request was closed without merging. The job is closed and the app lock released — re-run or reapply to try again.", nextPollSeconds: 0 },
    FAILED_ASSESS: { message: "Assessment failed. See error for details.",                  nextPollSeconds: 0  },
    FAILED_COMMIT: { message: "Commit/transform stage failed. See error for details.",      nextPollSeconds: 0  },
    FAILED_CI:     { message: "CI build/tests failed after merge. See error for details.",  nextPollSeconds: 0  },
    FAILED_DEPLOY: { message: "Deployment failed. See error for details.",                  nextPollSeconds: 0  },
    FAILED_INTERRUPTED: { message: "Upgrade was interrupted before completion (runtime restart/crash) and was automatically failed. Re-submit to retry.", nextPollSeconds: 0 }
}

/**
 * Builds the public JobStatus payload from a stored job record.
 * Optional fields (branchName/prUrl/prNumber/jiraTicketId/jiraUrl/completedAt/error)
 * are included only when present, preserving the original response shape exactly.
 *
 * @param rec         the persisted job record
 * @param jiraBaseUrl the Jira site base URL (e.g. https://acme.atlassian.net) used to
 *                    build a clickable jiraUrl; pass "" to omit the link.
 */
fun buildJobStatus(rec, jiraBaseUrl = "") = do {
    var meta = statusMeta[rec.status]
               default { message: ("Status: " ++ (rec.status default "UNKNOWN")), nextPollSeconds: 10 }
    // Sub-stage refinement: several fine-grained lifecycle stages intentionally share
    // one coarse RAML status value (the enum is fixed). We surface the finer stage
    // through the `message` field so callers/agents can tell them apart without an
    // enum change. Currently: "MUnit tests passed" is still PR_OPEN.
    var munitResult = (rec.munit.result default "") as String
    var message =
        if (rec.status == "PR_OPEN" and munitResult == "passed")
            "MUnit tests passed in CI. Pull request is open and ready for review/merge."
        else meta.message
    ---
    {
        jobId:           rec.jobId,
        status:          rec.status,
        message:         message,
        nextPollSeconds: meta.nextPollSeconds
    }
    ++ (if (rec.branchName  != null) { branchName:  rec.branchName  } else {})
    ++ (if (rec.prUrl       != null) { prUrl:        rec.prUrl       } else {})
    ++ (if (rec.prNumber    != null) { prNumber:     rec.prNumber    } else {})
    ++ (if (rec.jiraTicketId != null) { jiraTicketId: rec.jiraTicketId } else {})
    ++ (if (rec.jiraTicketId != null and jiraBaseUrl != "")
          { jiraUrl: (jiraBaseUrl ++ "/browse/" ++ (rec.jiraTicketId as String)) } else {})
    ++ (if (rec.completedAt != null) { completedAt:  rec.completedAt } else {})
    ++ (if (rec.error       != null) { error:        rec.error       } else {})
}
