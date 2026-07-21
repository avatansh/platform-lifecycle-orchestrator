%dw 2.0
/**
 * dwl::rewritePomVersion — bump the app module's OWN <project><version> to `newVersion`.
 *
 * Surgical + topology-safe: it rewrites ONLY the value inside the EXISTING <version> tag
 * that immediately follows the project's own <artifactId>. No new tag is ever added. The
 * <parent><version>, dependency <version>s and plugin <version>s are matched by a DIFFERENT
 * artifactId (or none) and are therefore never touched. This mirrors the "edit the app pom,
 * nothing else" contract of the appOverride strategy.
 *
 * No-op (returns the text unchanged) when the project artifactId is not found immediately
 * followed by a <version> — e.g. the version is inherited from the parent, declared before
 * the artifactId, or driven by a ${property} placeholder (that case is handled as a
 * pomProperty edit instead).
 *
 * @param pomText            raw pom.xml text (already base64-decoded)
 * @param projectArtifactId  the app module's own <artifactId>
 * @param newVersion         the minor-bumped version to write
 * @return                   rewritten pom.xml text
 */
fun rewritePomVersion(pomText: String, projectArtifactId: String, newVersion: String): String = do {
    var target = trim(projectArtifactId default "")
    ---
    if (target == "") pomText
    else
        // group1 = `<artifactId>…</artifactId>…<version>` (kept verbatim, incl. whitespace)
        // group2 = the artifactId inner text (used to confirm this is the PROJECT's version)
        // group3 = the closing `</version>` (kept verbatim)
        pomText replace /(<artifactId>\s*([^<]*?)\s*<\/artifactId>\s*<version>)\s*[^<]*?\s*(<\/version>)/
            with ((m, idx) ->
                if ((trim(m[2] default "")) == target)
                    ((m[1] default "") ++ newVersion ++ (m[3] default ""))
                else (m[0] default ""))
}
