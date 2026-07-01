%dw 2.0
/**
 * Surgically rewrite the <version> of specific <dependency> entries (matched by
 * groupId + artifactId) in a pom.xml, preserving every other byte. Used for apps
 * that pin a connector/module version INLINE on the dependency instead of via a
 * ${property}. Works on <dependencies> and <dependencyManagement> blocks alike.
 *
 * @param pomText  raw pom.xml text (already base64-decoded)
 * @param edits    array of objects shaped { groupId: String, artifactId: String, to: String, ... };
 *                 extra fields (file, from, kind, change, property) are ignored
 * @return         rewritten pom.xml text
 */
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
        if (hit != null)
            // Replace only the inline <version> literal; leaves ${...} refs untouched by design
            // (those are handled as pomProperty edits upstream).
            (block replace /<version>[^<$][^<]*<\/version>/ with ("<version>" ++ (hit.to as String) ++ "</version>"))
        else block
    })
