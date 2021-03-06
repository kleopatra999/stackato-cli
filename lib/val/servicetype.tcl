## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Service Type, aka Vendor
## Dependency: config @client      (possibilities)
## Dependency: @provider, @version (filtering)

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require dictutil
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/servicetype
debug prefix validate/servicetype {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export servicetype
    namespace ensemble create
}

namespace eval ::stackato::validate::servicetype {
    namespace export default validate complete release \
	get-candidates
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::mgr::corg
    namespace import ::stackato::v2
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::validate::common::expected
}

proc ::stackato::validate::servicetype::default  {p}   { return {} }
proc ::stackato::validate::servicetype::release  {p x} { return }
proc ::stackato::validate::servicetype::complete {p x} {
    if {![[refresh-client $p] isv2]} {
	# Against a v1 target we cannot complete.
	return {}
    }
    set possibles [struct::list map [get-candidates $p] [lambda s {$s @label}]]
    complete-enum $possibles 0 $x
}

proc ::stackato::validate::servicetype::validate {p x} {
    debug.validate/servicetype {}
    # Accept the default.
    if {$x eq {}} {
	debug.validate/servicetype {OK/default}
	return $x
    }

    if {![[refresh-client $p] isv2]} {
	# Against a v1 target we cannot validate and accept all
	debug.validate/servicetype {OK/v1 pass = $x}
	return $x
    }

    if {$x eq "user-provided"} {
	# See also servicemgr::SelectCreateV2
	set up [v2 service new]
	$up @label    set user-provided
	$up @version  set {}
	$up @provider set {}
	return $up
    }

    set matches [struct::list filter [get-candidates $p] [lambda {x s} {
	string equal [$s @label] $x
    } $x]]

    if {[llength $matches] == 1} {
	# Found, good.
	set x [lindex $matches 0]
	debug.validate/servicetype {OK/canon = $x}
	return $x
    }
    debug.validate/servicetype {FAIL}
    expected $p SERVICETYPE "service" $x [FilterHint $p]
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::validate::servicetype::get-candidates {p} {
    debug.validate/servicetype {}

    # See also app.tcl, LocateService2, for equivalent code, based on
    # different input (manifest service specification).
    #
    # TODO/FUTURE: See if we can consolidate and refactor here and
    # there.

    # Get available services.
    set services [v2 service list 1]
    debug.validate/servicetype {retrieved      = $services}

    # Drop inactive service types
    set services [struct::list filter $services [lambda {s} {
	$s @active
    }]]
    debug.validate/servicetype {active         = $services}

    # config @vendor   - service @label
    # config @provider - service @provider
    # config @version  - service @version

    # Filter by provider
    if {[$p config @provider set?]} {
	set pattern [$p config @provider]
	set services [struct::list filter $services [lambda {p s} {
	    string equal $p [$s @provider]
	} $pattern]]
	debug.validate/servicetype {provider-match = $services}
    }

    # Filter by version
    if {[$p config @version set?]} {
	set pattern [$p config @version]
	set services [struct::list filter $services [lambda {p s} {
	    string equal $p [$s @version]
	} $pattern]]
	debug.validate/servicetype {version-match  = $services}
    }

    debug.validate/servicetype {==> $services}
    return $services
}

proc ::stackato::validate::servicetype::FilterHint {p} {
    if {
	[$p config @provider set?] &&
	[$p config @version set?]
    } {
	set p [$p config @provider]
	set v [$p config @version]
	return "(with provider '$p', and version $v)"
    }
    if {[$p config @provider set?]} {
	set p [$p config @provider]
	return " (with provider '$p')"
    }
    if {[$p config @version set?]} {
	set v [$p config @version]
	return " (with version $v)"
    }
    return ""
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::servicetype 0
