%dw 2.0
/**
 * Surgically pin the <version> of specific <dependency> entries (matched by
 * groupId + artifactId) in a pom.xml, preserving every other byte. Backs the appOverride
 * strategy: every declared connector/module gets an explicit, Java-17-compatible version in
 * the app's own pom. Works on <dependencies> and <dependencyManagement> blocks alike.
 *
 * For a matched dependency block:
 *   · an existing <version> (literal OR ${…} placeholder) is REPLACED with the pinned literal;
 *   · a BOM-managed dependency with NO <version> gets one INSERTED after its </artifactId>.
 * A dependency the app doesn't declare is never touched — the caller only passes edits for
 * coordinates already present in the app pom.
 *
 * @param pomText  raw pom.xml text (already base64-decoded)
 * @param edits    array of objects shaped { groupId: String, artifactId: String, to: String, ... };
 *                 extra fields (file, from, kind, change, property) are ignored
 * @return         rewritten pom.xml text
 */
import substringBefore, substringAfter from dw::core::Strings

fun rewriteDepVersions(pomText: String, edits: Array): String =
    // Match each <dependency>…</dependency> block (non-greedy; blocks never nest).
    pomText replace /<dependency>[\s\S]*?<\/dependency>/ with ((m, idx) -> do {
        var block = m[0]
        // First edit whose g:a coordinates appear inside THIS block.
        var hit = (edits filter ((e) ->
            (block contains ("<groupId>" ++ (e.groupId as String) ++ "</groupId>")) and
            (block contains ("<artifactId>" ++ (e.artifactId as String) ++ "</artifactId>"))
        ))[0]
        ---
        if (hit == null) block
        else if (block contains "<version>")
            // Replace the dependency's inline <version> — literal or ${…} ref — with the pin.
            (block replace /<version>[^<]*<\/version>/ with ("<version>" ++ (hit.to as String) ++ "</version>"))
        else
            // BOM-managed dependency (no <version>) → insert one after the FIRST </artifactId>
            // (the dependency's own; any <exclusion> artifactIds come after it).
            ((block substringBefore "</artifactId>") ++ "</artifactId>"
             ++ "\n            <version>" ++ (hit.to as String) ++ "</version>"
             ++ (block substringAfter "</artifactId>"))
    })
