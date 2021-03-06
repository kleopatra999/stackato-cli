## -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## Stackato - Validation Type - Service Broker Name, Not
## Dependency: config @client

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require struct::list
package require lambda
package require cmdr::validate
package require stackato::mgr::client;# pulls v2 also
package require stackato::validate::common

debug level  validate/notservicebroker
debug prefix validate/notservicebroker {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Definition

namespace eval ::stackato::validate {
    namespace export notservicebroker
    namespace ensemble create
}

namespace eval ::stackato::validate::notservicebroker {
    namespace export default validate complete release
    namespace ensemble create

    namespace import ::cmdr::validate::common::complete-enum
    namespace import ::stackato::validate::common::refresh-client
    namespace import ::stackato::validate::common::not
    namespace import ::stackato::mgr::cspace
    namespace import ::stackato::v2
}

proc ::stackato::validate::notservicebroker::default  {p}   { return {} }
proc ::stackato::validate::notservicebroker::release  {p x} { return }
proc ::stackato::validate::notservicebroker::complete {p x} { return {} }

proc ::stackato::validate::notservicebroker::validate {p x} {
    debug.validate/notservicebroker {}

    refresh-client $p

    set matches [struct::list filter [v2 service_broker list] [lambda {x o} {
	string equal $x	[$o @name]
    } $x]]

    if {![llength $matches]} {
	debug.validate/notservicebroker {OK/canon = $x}
	return $x
    }
    debug.validate/notservicebroker {FAIL}
    not $p NOTSERVICEBROKER "service broker" $x
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::validate::notservicebroker 0
