%dw 2.0
/**
 * dwl::dates — shared timestamp helpers.
 *
 * Pure module: no reliance on Mule context (vars/payload/p()). Safe to import
 * from any transform or other DWL module.
 */

/**
 * Current instant as a canonical UTC ISO-8601 string, e.g. "2026-07-07T12:00:00Z".
 * Used for every createdAt / updatedAt / completedAt field on job records so the
 * format is defined in exactly one place.
 */
fun nowUtc(): String = (now() >> |+00:00|) as String {format: "yyyy-MM-dd'T'HH:mm:ss'Z'"}
