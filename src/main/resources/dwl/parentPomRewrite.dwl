%dw 2.0
/**
 * dwl::parentPomRewrite — pin the connector versions MANAGED by a shared parent/BOM pom.xml
 * to the Java-17 compatibility matrix, preserving every other byte of the file.
 *
 * Backs POST /parent-pom/upgrade (pf-upgrade-parent-pom). Complements the app upgrade: apps that
 * inherit versions from a parent/BOM only get gating edits + a connectorGaps warning; THIS fixes
 * the connectors at the source. Only connectors the parent already MANAGES are touched — a
 * connector absent from the parent is never added (we never invent dependencies).
 *
 * A managed connector is pinned wherever the parent controls it:
 *   · a <properties> entry (e.g. <http.connector.version>1.7.2</…>) referenced by
 *     <dependencyManagement> → the property value is bumped (one edit fixes every reference),
 *   · a literal inline <version> on a <dependencyManagement>/<dependencies> entry → replaced.
 * A ${ref} inline version is driven by its property, so it is handled by the property path.
 *
 * Pure module: pass in the raw (base64-decoded) pom text + the matrix; returns the rewritten
 * text and the applied edit list. Independently unit-testable.
 */
import substringBefore, substringAfter from dw::core::Strings

// ── semver helpers: simple "a < b" over major.minor.patch ─────────────────────────────
fun toNums(v) = ((v default "0") splitBy ".") map (trim($) replace /[^0-9].*/ with "") map (($ default "0") as Number)
fun lt(a, b) = do {
    var x = toNums(a)
    var y = toNums(b)
    --- (x[0] default 0) < (y[0] default 0) or
        ((x[0] default 0) == (y[0] default 0) and (x[1] default 0) < (y[1] default 0)) or
        ((x[0] default 0) == (y[0] default 0) and (x[1] default 0) == (y[1] default 0) and (x[2] default 0) < (y[2] default 0))
}

// Only matrix connectors carrying full coordinates + a property key are eligible.
fun connRules(matrix) =
    ((matrix.connectors default []) filter ((r) -> (r.groupId?) and (r.artifactId?) and (r.property?)))

// Raw inner text of the FIRST <prop>…</prop> occurrence (null when absent or malformed).
// Returns the UNTRIMMED inner so the exact literal can be replaced without disturbing whitespace.
fun propInner(pomText: String, prop: String) = do {
    var open  = "<" ++ prop ++ ">"
    var close = "</" ++ prop ++ ">"
    ---
    if (pomText contains open) do {
        var inner = (pomText substringAfter open) substringBefore close
        --- if (inner contains "<") null else inner   // close tag not found before the next element
    } else null
}

// Literal inline <version> of the dependency block for g:a, "REF" when it is a ${…} placeholder,
// or null when the block/version is absent.
fun inlineDepVersion(pomText: String, g: String, a: String) = do {
    var blocks = (pomText scan /<dependency>[\s\S]*?<\/dependency>/)
    var hit = (blocks filter ((m) ->
        ((m[0]) contains ("<groupId>" ++ g ++ "</groupId>")) and
        ((m[0]) contains ("<artifactId>" ++ a ++ "</artifactId>"))))[0]
    ---
    if (hit == null) null
    else if (!((hit[0]) contains "<version>")) null
    else do {
        var v = trim(((hit[0]) substringAfter "<version>") substringBefore "</version>")
        --- if (v matches /^\s*\$\{.+\}\s*$/) "REF" else v
    }
}

// Compute the edit list: for each managed connector below target, one edit tagged with how to
// apply it (mode=prop → replace the property value; mode=inline → replace the dependency version).
fun computeParentEdits(pomText: String, matrix, pomPath) =
    (connRules(matrix)
        map ((r) -> do {
            var prop   = (r.property as String)
            var g      = (r.groupId as String)
            var a      = (r.artifactId as String)
            var pInner = propInner(pomText, prop)
            var pTrim  = if (pInner != null) trim(pInner) else null
            var inline = if (pInner == null) inlineDepVersion(pomText, g, a) else null
            ---
            if (pInner != null and lt(pTrim, (r.set as String)))
                { kind: "pomProperty", mode: "prop", file: pomPath, property: prop,
                  groupId: g, artifactId: a, from: pTrim, to: (r.set as String), inner: pInner, change: true }
            else if (inline != null and inline != "REF" and lt(inline, (r.set as String)))
                { kind: "depVersion", mode: "inline", file: pomPath, property: prop,
                  groupId: g, artifactId: a, from: inline, to: (r.set as String), change: true }
            else null
        })
        filter ($ != null)
        distinctBy ((e) -> e.groupId ++ ":" ++ e.artifactId))

// Apply the edits to the text: literal property replacements first, then inline version blocks.
fun applyParentEdits(pomText: String, edits): String = do {
    var afterProps = (edits filter ($.mode == "prop"))
        reduce ((e, acc = pomText) ->
            acc replace ("<" ++ e.property ++ ">" ++ e.inner ++ "</" ++ e.property ++ ">")
                with ("<" ++ e.property ++ ">" ++ (e.to as String) ++ "</" ++ e.property ++ ">"))
    var inlineEdits = (edits filter ($.mode == "inline"))
    ---
    if (isEmpty(inlineEdits)) afterProps
    else (afterProps replace /<dependency>[\s\S]*?<\/dependency>/ with ((m, idx) -> do {
        var block = m[0]
        var hit = (inlineEdits filter ((e) ->
            (block contains ("<groupId>" ++ (e.groupId as String) ++ "</groupId>")) and
            (block contains ("<artifactId>" ++ (e.artifactId as String) ++ "</artifactId>"))))[0]
        ---
        if (hit == null) block
        else (block replace /<version>[^<]*<\/version>/ with ("<version>" ++ (hit.to as String) ++ "</version>"))
    }))
}

/**
 * Rewrite a parent/BOM pom text, pinning managed connectors to the matrix.
 * @return { text: rewritten pom text, edits: FileEdit-shaped array (empty when already compliant) }
 */
fun rewriteParentPom(pomText: String, matrix, pomPath = "pom.xml") = do {
    var edits = computeParentEdits(pomText, matrix, pomPath)
    ---
    {
        text:  applyParentEdits(pomText, edits),
        edits: (edits map ((e) ->
            { kind: e.kind, file: e.file, property: e.property, groupId: e.groupId,
              artifactId: e.artifactId, from: e.from, to: e.to, change: true }))
    }
}
