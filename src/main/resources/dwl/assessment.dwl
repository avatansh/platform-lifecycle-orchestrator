%dw 2.0
/**
 * dwl::assessment — the Java 17 upgrade assessment engine. Applies the compatibility
 * matrix to a resolved pom inheritance chain and produces the AssessmentResult payload.
 *
 * Pure module: chain + matrix + decoded file text are passed in explicitly, so every
 * function here is independently unit-testable (see dw-assessment-suite.xml).
 */
import propOf from dwl::pomChain
import * from dw::core::Strings

// ── semver helpers: simple "a < b" comparison over major.minor.patch ──────────────
fun toNums(v) = (v splitBy ".") map (trim($) replace /[^0-9].*/ with "") map (($ default "0") as Number)
fun lt(a, b) = do {
    var x = toNums(a)
    var y = toNums(b)
    --- (x[0] default 0) < (y[0] default 0) or
        ((x[0] default 0) == (y[0] default 0) and (x[1] default 0) < (y[1] default 0)) or
        ((x[0] default 0) == (y[0] default 0) and (x[1] default 0) == (y[1] default 0) and (x[2] default 0) < (y[2] default 0))
}

// rawProp(name): first non-null property value across the chain (nearest-first), no indirection.
fun rawProp(chain, name) = ((chain map ((c) -> propOf(c.pom, name))) filter ($ != null))[0] default null

// resolveProp(name): rawProp, following ONE level of Maven property-placeholder indirection.
fun resolveProp(chain, name) = do {
    var v = rawProp(chain, name)
    --- if (v != null and ((v as String) matches /^\s*\$\{.+\}\s*$/))
            rawProp(chain, (trim(v as String) replace /^\$\{/ with "" replace /\}$/ with ""))
        else v
}

// ownerOfProp(name): path of the nearest chain pom that declares the property, else null.
fun ownerOfProp(chain, name) =
    ((chain filter ((c) -> propOf(c.pom, name) != null))[0]).path default null

// findDep(g,a): nearest chain entry declaring dependency g:a in <dependencies> or
// <dependencyManagement>, returned as { path, dep }, else null.
fun findDep(chain, g, a) =
    (flatten(chain map ((c) -> do {
        var deps = ((c.pom.project.dependencies default {}).*dependency) default []
        var mgmt = ((c.pom.project.dependencyManagement.dependencies default {}).*dependency) default []
        --- (deps ++ mgmt) map ((d) -> { path: c.path, dep: d })
    })) filter ((x) ->
        (((x.dep.groupId default "") as String) == g) and
        (((x.dep.artifactId default "") as String) == a)))[0] default null

// findPlugin(g,a): nearest chain entry declaring plugin a in <build><plugins> or
// <build><pluginManagement><plugins>, returned as { path, plugin }, else null.
// groupId is optional (plugins are commonly identified by artifactId alone).
fun findPlugin(chain, g, a) =
    (flatten(chain map ((c) -> do {
        var ps  = ((c.pom.project.build.plugins default {}).*plugin) default []
        var pms = ((c.pom.project.build.pluginManagement.plugins default {}).*plugin) default []
        --- (ps ++ pms) map ((p) -> { path: c.path, plugin: p })
    })) filter ((x) ->
        (((x.plugin.artifactId default "") as String) == a) and
        (g == null or (((x.plugin.groupId default "") as String) == g))))[0] default null

// resolveInline(r, ver, path, kind, coords): shared handling for an inline <version> found
// on a dependency or plugin — null → skip; property-placeholder → resolve as pomProperty on
// the referenced property; literal → emit `kind` carrying the given coordinate fields.
fun resolveInline(chain, r, ver, path, kind, coords) =
    if (ver == null) { property: r.property, kind: null, file: null, installed: null }
    else if ((ver as String) matches /^\s*\$\{.+\}\s*$/) do {
        var pn = (trim(ver as String) replace /^\$\{/ with "" replace /\}$/ with "")
        --- { property: pn, kind: "pomProperty", file: (ownerOfProp(chain, pn) default path), installed: rawProp(chain, pn) }
    }
    else
        ({ property: r.property, kind: kind, file: path, installed: (ver as String) } ++ coords)

// resolveRule(r): find installed value + owner file + edit kind. Resolution order:
//   1) <properties> value (kind=pomProperty)
//   2) inline <dependency>/<dependencyManagement> <version> (kind=depVersion)
//   3) inline <plugin> <version> (kind=pluginVersion)
// An inline value that is itself a property placeholder collapses back to a pomProperty edit.
fun resolveRule(chain, r) = do {
    var pOwner = ownerOfProp(chain, r.property)
    var depHit = if ((r.groupId?) and (r.artifactId?)) findDep(chain, r.groupId, r.artifactId) else null
    var plgHit = if (r.pluginArtifactId?) findPlugin(chain, (r.pluginGroupId default null), r.pluginArtifactId) else null
    ---
    if (pOwner != null)
        { property: r.property, kind: "pomProperty", file: pOwner, installed: rawProp(chain, r.property) }
    else if (depHit != null)
        resolveInline(chain, r, (depHit.dep.version default null), depHit.path, "depVersion",
                      { groupId: r.groupId, artifactId: r.artifactId })
    else if (plgHit != null)
        resolveInline(chain, r, (plgHit.plugin.version default null), plgHit.path, "pluginVersion",
                      { pluginGroupId: (r.pluginGroupId default null), pluginArtifactId: r.pluginArtifactId })
    else { property: r.property, kind: null, file: null, installed: null }
}

/**
 * Computes the property/dependency/plugin edit list from the gating + connector rules.
 * Each edit carries its OWN owner file + kind; only edits that actually change are kept.
 */
fun computePropEdits(chain, matrix) =
    ((valuesOf(matrix.gating) ++ matrix.connectors)
        map ((r) -> do {
            var res       = resolveRule(chain, r)
            var installed = res.installed
            var needs     = if (installed == null or res.kind == null) false   // not present → skip
                            else if (r.in?)  (r.in contains installed)
                            else lt(installed, r.set)
            ---
            {
                property:         res.property,
                kind:             res.kind,
                file:             res.file,
                (groupId:          res.groupId)          if (res.groupId?),
                (artifactId:       res.artifactId)       if (res.artifactId?),
                (pluginGroupId:    res.pluginGroupId)    if (res.pluginGroupId?),
                (pluginArtifactId: res.pluginArtifactId) if (res.pluginArtifactId?),
                from:             installed,
                to:               r.set,
                change:           needs
            } })
        filter ($.change))

/**
 * Scans the repo tree + app pom text for custom Java, lookup() usage and builds warnings.
 * tree       : recursive tree object
 * appPomText : decoded app pom text
 */
fun scanFlags(tree, appPomText) = do {
    // Custom Java: any .java file anywhere in the repository tree
    var javaFiles      = tree.tree filter ($.path matches /.*\.java$/)
    var customJava     = !isEmpty(javaFiles)
    // lookup(): scan raw app pom text as a fast heuristic
    var lookupInPom    = appPomText contains "lookup("
    var truncWarning   = if (tree.truncated default false)
                             ["Repository tree was truncated by GitHub (>100k objects); some file paths may have been missed."]
                         else []
    var javaWarning    = if (customJava)
                             ["Custom Java classes detected (" ++ sizeOf(javaFiles) ++ " file(s)). Verify reflection and SecurityManager usage on JDK 17."]
                         else []
    var lookupWarning  = if (lookupInPom)
                             ["lookup() reference found in pom text; scan Mule XMLs to confirm DataWeave POJO lookup usage requiring getter/setter validation."]
                         else []
    ---
    {
        customJavaFound: customJava,
        lookupFound:     lookupInPom,
        hasApiPolicies:  false,    // TODO: query Anypoint API Manager for applied policies
        warnings:        truncWarning ++ javaWarning ++ lookupWarning
    }
}

/**
 * Builds the full AssessmentResult payload. All matrix rules are applied to the installed
 * property/dependency/plugin values, then app-level (MUnit runtimeVersion, mule-artifact.json,
 * CI workflow) diff-aware edits are added.
 */
fun buildAssessmentResult(
        matrix, chain, appPomText0, muleArtifactCurrent, muleArtifactPath,
        ciWorkflowText, ciWorkflowPath, appName, topology, headSha,
        hasApiPolicies, customJavaFound, lookupFound, warnings) = do {
    var m = matrix
    var propEdits = computePropEdits(chain, matrix)
    // app-level edits — DIFF-AWARE: emit ONLY when the current value actually differs from target.
    var appPomText = appPomText0 default ""
    // (1) MUnit <runtimeVersion> — literal only. A property-placeholder value is driven by a
    //     property, so it is handled by the property path above and must NOT be rewritten here.
    var munitCur         = (appPomText scan /<runtimeVersion>\s*([^<]+?)\s*<\/runtimeVersion>/)[0][1] default null
    var munitPlaceholder = (munitCur != null) and ((munitCur default "") matches /^\s*\$\{.+\}\s*$/)
    var munitNeeds       = (munitCur != null) and (!munitPlaceholder) and lt((munitCur as String), m.target.runtime)
    // (2) mule-artifact.json — bump minMuleVersion only if BELOW target (never downgrade); ensure
    //     java target support only if no current spec is already >= target (handles "1.8"/"8"/"11").
    var maCur      = muleArtifactCurrent
    var maSpecs    = (maCur.javaSpecificationVersions default [])
    var maMinNeeds = (maCur != null) and lt((maCur.minMuleVersion default "0"), m.muleArtifact.minMuleVersion)
    var maJavaOk   = !isEmpty(maSpecs filter ((s) -> !lt((s as String), m.target.javaVersion)))
    var maJavaNeeds= (maCur != null) and (!maJavaOk)
    var maNeeds    = maMinNeeds or maJavaNeeds
    // Never downgrade minMuleVersion: keep current when it is already at/above target.
    var maToMin    = if (maMinNeeds) m.muleArtifact.minMuleVersion else (maCur.minMuleVersion default m.muleArtifact.minMuleVersion)
    // (3) CI workflow — bump only if the current java-version is below target (never downgrade).
    var ciCur      = ((ciWorkflowText default "") scan /java-version:\s*['"]?([^'"\s]+)['"]?/)[0][1] default null
    var ciNeeds    = (ciCur != null) and lt((ciCur as String), m.target.javaVersion)
    var appEdits = []
      ++ (if (munitNeeds)
            [{ file: chain[0].path, kind: "munitRuntimeVersion", from: munitCur, to: m.target.runtime }] else [])
      ++ (if (maNeeds)
            [{ file: muleArtifactPath, kind: "muleArtifactJson",
               from: { minMuleVersion: (maCur.minMuleVersion default null), javaSpecificationVersions: maSpecs },
               to: { minMuleVersion: maToMin,
                     javaSpecificationVersions: m.muleArtifact.javaSpecificationVersions } }] else [])
      ++ (if (ciNeeds)
            [{ file: ciWorkflowPath, kind: "ciWorkflow", from: ciCur, to: m.target.javaVersion }] else [])
    var all = propEdits ++ appEdits
    // BLAST-RADIUS: property/dependency/plugin edits can land on a shared parent or BOM
    // pom (any chain entry other than the app's OWN module pom at chain[0]). Editing those
    // upgrades every module that inherits from them, so surface it as an explicit warning.
    var appPomPath     = chain[0].path default ''
    var sharedPomFiles = ((propEdits map $.file) distinctBy $) filter ((f) -> f != appPomPath)
    var blastWarnings  = if (isEmpty(sharedPomFiles)) []
        else [ ("BLAST RADIUS: this upgrade edits shared build file(s) [" ++ (sharedPomFiles joinBy ", ")
                ++ "] that are inherited by other modules in the repository. Approving it upgrades EVERY module that inherits from these files, not just "
                ++ (appName default "this app")
                ++ " — every inheriting module's build and MUnit tests must pass in CI. Review the wider impact before approving.") ]
    ---
    {
      appName: appName,
      currentRuntime: resolveProp(chain, "app.runtime") default resolveProp(chain, "app.runtime.semver") default "unknown",
      currentJavaVersion: resolveProp(chain, "java.version") default resolveProp(chain, "maven.compiler.source") default resolveProp(chain, "maven.compiler.target") default "unknown",
      changePlan: {
        targetRuntime:     m.target.runtime,
        targetJavaVersion: m.target.javaVersion,
        topology:          topology,
        headSha:           headSha,
        fileEdits:         all,
        filesToChange:     (all map $.file) distinctBy $,
        hasApiPolicies:    hasApiPolicies default false,
        hasCustomJavaCode: customJavaFound default false,
        hasLookupFunction: lookupFound default false
      },
      warnings: (warnings default []) ++ blastWarnings
    }
}
