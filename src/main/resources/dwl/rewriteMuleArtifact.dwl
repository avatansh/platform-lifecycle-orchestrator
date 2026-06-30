%dw 2.0
/**
 * Update mule-artifact.json: set minMuleVersion and (re)add javaSpecificationVersions,
 * PRESERVING every other existing key. The demo file only has { "minMuleVersion": "4.4.0" },
 * so javaSpecificationVersions must be ADDED, not just replaced. Re-serialised as pretty JSON.
 *
 * @param currentText      raw mule-artifact.json text
 * @param minMuleVersion   e.g. "4.9.0"
 * @param javaSpecVersions e.g. ["17"]
 */
fun rewriteMuleArtifact(currentText: String, minMuleVersion: String, javaSpecVersions: Array): String = do {
    var current = read(currentText, "application/json")
    // remove the two keys we own (no-op if absent) so the merge can't create duplicates
    var base    = (current default {}) - "minMuleVersion" - "javaSpecificationVersions"
    ---
    write(
        base ++ { minMuleVersion: minMuleVersion, javaSpecificationVersions: javaSpecVersions },
        "application/json",
        { indent: true }
    )
}