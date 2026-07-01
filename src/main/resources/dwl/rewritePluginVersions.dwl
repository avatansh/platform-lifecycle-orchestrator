%dw 2.0
/**
 * Surgically rewrite the <version> of specific <plugin> entries (matched by
 * artifactId, optionally groupId) in a pom.xml, preserving every other byte. Used
 * for apps that pin a build-plugin version INLINE on the plugin instead of via a
 * property placeholder. Works on <build><plugins> and <pluginManagement> alike.
 *
 * Only the plugin's OWN <version> (the first one in the block) is rewritten — any
 * <version> tags belonging to dependencies nested inside the <plugin> are left alone.
 *
 * @param pomText  raw pom.xml text (already base64-decoded)
 * @param edits    array of objects shaped { pluginArtifactId: String, to: String,
 *                 pluginGroupId: String|null, ... }; extra fields are ignored
 * @return         rewritten pom.xml text
 */
fun rewritePluginVersions(pomText: String, edits: Array): String =
    // Match each <plugin>…</plugin> block (non-greedy; plugin blocks never nest).
    pomText replace /<plugin>[\s\S]*?<\/plugin>/ with ((m, idx) -> do {
        var block = m[0]
        // First edit whose plugin coordinates appear inside THIS block (groupId optional).
        var hit = (edits filter ((e) ->
            (block contains ("<artifactId>" ++ (e.pluginArtifactId as String) ++ "</artifactId>")) and
            ((e.pluginGroupId == null) or
             (block contains ("<groupId>" ++ (e.pluginGroupId as String) ++ "</groupId>")))
        ))[0]
        ---
        if (hit != null)
            // Anchored, non-greedy prefix guarantees we replace only the FIRST <version>
            // (the plugin's own literal version), not a nested dependency's version.
            (block replace /^([\s\S]*?)<version>[^<$][^<]*<\/version>/
                with ((v, vi) -> (v[1] default "") ++ "<version>" ++ (hit.to as String) ++ "</version>"))
        else block
    })
