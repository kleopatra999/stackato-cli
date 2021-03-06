# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations. User management.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require stackato::color
package require stackato::jmap
package require stackato::log
package require stackato::v2
package require table

debug level  cmd/servicebroker
debug prefix cmd/servicebroker {[debug caller] | }

namespace eval ::stackato::cmd {
    namespace export servicebroker
    namespace ensemble create
}
namespace eval ::stackato::cmd::servicebroker {
    namespace export list add update remove
    namespace ensemble create

    namespace import ::stackato::color
    namespace import ::stackato::jmap
    namespace import ::stackato::log::display
    namespace import ::stackato::v2
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicebroker::list {config} {
    debug.cmd/servicebroker {}

    set thebrokers [v2 service_broker list]

    if {[$config @json]} {
	set tmp {}
	foreach broker $thebrokers {
	    lappend tmp [$broker as-json]
	}
	display [json::write array {*}$tmp]
	return
    }

    if {![llength $thebrokers]} {
	display "No service brokers available"
	debug.cmd/servicebroker {/done NONE}
	return
    }

    # Extract the information we wish to show.
    # Having it in list form makes sorting easier, later.

    foreach broker $thebrokers {
	set name [$broker @name]
	set url  [$broker @broker_url]

	lappend details $name $url
	lappend brokers $details
	unset details
    }

    # Now format and display the table
    [table::do t {Name Url} {
	foreach tok [lsort -dict $brokers] {
	    $t add {*}$tok
	}
    }] show display

    debug.cmd/servicebroker {/done OK}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicebroker::add {config} {
    debug.cmd/servicebroker {}
    # V2 only.
    # client v2 = @service is entity instance

    # @name         string
    # @url          string
    # @broker-token string

    set broker [v2 service_broker new]

    display "Adding service broker \[[$config @name]\] ... " false

    $broker @name       set [$config @name]
    $broker @broker_url set [$config @url]
    $broker @token      set [$config @broker-token]

    $broker commit
    display [color green OK]

    debug.cmd/servicebroker {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicebroker::remove {config} {
    debug.cmd/servicebroker {}
    # V2 only.
    # client v2 = @name is entity instance

    set broker [$config @name]

    display "Deleting service broker \[[$broker @name]\] ... " false
    $broker delete
    $broker commit
    display [color green OK]

    debug.cmd/servicebroker {/done}
    return
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::cmd::servicebroker::update {config} {
    debug.cmd/servicebroker {}
    # V2 only.
    # client v2 = @name is entity instance

    set broker [$config @name]
    set changes 0

    display "Updating broker \[[$broker @name]\] ..."

    if {[$config @newname set?]} {
	$broker @name set [$config @newname]
	display "  Changed name  to [$config @newname]"
	incr changes
    }
    if {[$config @url set?]} {
	$broker @broker_url set [$config @url]
	display "  Changed url   to [$config @url]"
	incr changes
    }
    if {[$config @broker-token set?]} {
	$broker @token set [$config @broker-token]
	display "  Changed token to [$config @broker-token]"
	incr changes
    }

    if {$changes} {
	$broker commit
	display [color green OK]
    } else {
	display "No changes made."
    }

    debug.cmd/servicebroker {/done}
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::servicebroker 0
return
