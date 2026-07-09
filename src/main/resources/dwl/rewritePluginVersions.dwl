%dw 2.0
/**
 * Surgically pin the <version> of specific <plugin> entries (matched by artifactId,
 * optionally groupId) in a pom.xml, preserving every other byte. Backs the appOverride
 * strategy for build plugins (e.g. munit-maven-plugin). Works on <build><plugins> and
 * <pluginManagement> alike.
 *
 * Only the plugin's OWN <version> (the first one in the block) is affected — any <version>
 * tags belonging to dependencies nested inside the <plugin> are left alone:
 *   · an existing plugin <version> (literal OR ${…} placeholder) is REPLACED with the pin;
 *   · a plugin with NO <version> at all gets one INSERTED after its </artifactId>.
 *
 * @param pomText  raw pom.xml text (already base64-decoded)
 * @param edits    array of objects shaped { pluginArtifactId: String, to: String,
 *                 pluginGroupId: String|null, ... }; extra fields are ignored
 * @return         rewritten pom.xml text
 */
import substringBefore, substringAfter from dw::core::Strings

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
        if (hit == null) block
        else if (block contains "<version>")
            // Anchored, non-greedy prefix guarantees we replace only the FIRST <version>
            // (the plugin's own version — literal or ${…}), not a nested dependency's version.
            (block replace /^([\s\S]*?)<version>[^<]*<\/version>/
                with ((v, vi) -> (v[1] default "") ++ "<version>" ++ (hit.to as String) ++ "</version>"))
        else
            // Plugin with no version at all → insert after the plugin's own </artifactId>.
            ((block substringBefore "</artifactId>") ++ "</artifactId>"
             ++ "\n                <version>" ++ (hit.to as String) ++ "</version>"
             ++ (block substringAfter "</artifactId>"))
    })
