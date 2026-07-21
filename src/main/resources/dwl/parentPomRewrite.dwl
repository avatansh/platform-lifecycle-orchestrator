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
 * On top of the connector pins, when (and only when) at least one connector edit is made, the
 * parent/BOM's OWN <version> is minor-bumped in place (parity with the app upgrade path) so the
 * shared artifact gets a new release coordinate. No <version> tag is ever added.
 *
 * Pure module: pass in the raw (base64-decoded) pom text + the matrix; returns the rewritten
 * text and the applied edit list. Independently unit-testable.
 */
import substringBefore, substringAfter from dw::core::Strings
import rewritePomVersion from dwl::rewritePomVersion

// ── semver helpers: simple "a < b" over major.minor.patch ─────────────────────────────
fun toNums(v) = ((v default "0") splitBy ".") map (trim($) replace /[^0-9].*/ with "") map (($ default "0") as Number)
fun lt(a, b) = do {
    var x = toNums(a)
    var y = toNums(b)
    --- (x[0] default 0) < (y[0] default 0) or
        ((x[0] default 0) == (y[0] default 0) and (x[1] default 0) < (y[1] default 0)) or
        ((x[0] default 0) == (y[0] default 0) and (x[1] default 0) == (y[1] default 0) and (x[2] default 0) < (y[2] default 0))
}

// bumpMinor(v): increment the MINOR segment of a semver (resetting patch to 0), preserving any
// -qualifier.  "1.0.3-SNAPSHOT" -> "1.1.0-SNAPSHOT",  "2.3" -> "2.4.0",  "1" -> "1.1.0".
fun bumpMinor(v) = do {
    var s         = (v default "") as String
    var hasQual   = s contains "-"
    var core      = if (hasQual) substringBefore(s, "-") else s
    var qualifier = if (hasQual) ("-" ++ substringAfter(s, "-")) else ""
    var parts     = core splitBy "."
    var minor     = ((parts[1] default "0") as Number) + 1
    --- (parts[0] default "0") ++ "." ++ (minor as String) ++ ".0" ++ qualifier
}

// Remove the first <parent>…</parent> block so the pom's OWN coordinates (which follow it) can
// be isolated from the parent's groupId/artifactId/version.
fun stripParentBlock(pomText: String) = pomText replace /<parent>[\s\S]*?<\/parent>/ with ""

// The pom's OWN { artifactId, version }: the first <artifactId>…</artifactId><version>…</version>
// pair once the <parent> block is removed (conventional groupId/artifactId/version order). Null
// when the pom does not declare its own version inline.
fun projectCoords(pomText: String) = do {
    var noParent = stripParentBlock(pomText)
    var m = (noParent scan /<artifactId>\s*([^<]*?)\s*<\/artifactId>\s*<version>\s*([^<]*?)\s*<\/version>/)[0]
    --- if (m == null) null else { artifactId: trim(m[1] default ""), version: trim(m[2] default "") }
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
 * Rewrite a parent/BOM pom text, pinning managed connectors to the matrix and (when any
 * connector was pinned) minor-bumping the parent/BOM's OWN <version>.
 * @return { text: rewritten pom text, edits: FileEdit-shaped array (empty when already compliant) }
 */
fun rewriteParentPom(pomText: String, matrix, pomPath = "pom.xml") = do {
    var edits           = computeParentEdits(pomText, matrix, pomPath)
    var afterConnectors = applyParentEdits(pomText, edits)
    var connEdits       = (edits map ((e) ->
        { kind: e.kind, file: e.file, property: e.property, groupId: e.groupId,
          artifactId: e.artifactId, from: e.from, to: e.to, change: true }))
    // Self-bump the parent/BOM's own <version> — ONLY when at least one connector was pinned
    // (never bump on a no-change run) and the pom declares its own LITERAL version inline
    // (a ${property}-driven or inherited version is left alone). Rewrites the value inside the
    // EXISTING <version> tag; no tag is added.
    var coords    = projectCoords(pomText)
    var doBump    = (!isEmpty(edits)) and (coords != null)
                    and ((coords.version default "") != "")
                    and (!((coords.version as String) matches /^\s*\$\{.+\}\s*$/))
    var newVer    = if (doBump) bumpMinor(coords.version as String) else null
    var finalText = if (doBump) rewritePomVersion(afterConnectors, (coords.artifactId as String), (newVer as String)) else afterConnectors
    var versionEdit = if (doBump)
        [{ kind: "pomVersion", file: pomPath, artifactId: (coords.artifactId as String),
           from: (coords.version as String), to: (newVer as String), change: true }] else []
    ---
    {
        text:  finalText,
        edits: connEdits ++ versionEdit
    }
}
