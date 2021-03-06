# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Command implementations.
## Alias commands on top of the alias manager.

# # ## ### ##### ######## ############# #####################
## Requisites

package require Tcl 8.5
package require table
package require stackato::jmap
package require stackato::log
package require stackato::color
package require stackato::mgr::alias

namespace eval ::stackato::cmd {
    namespace export alias
    namespace ensemble create
}
namespace eval ::stackato::cmd::alias {
    namespace import ::stackato::log::err
    namespace import ::stackato::log::say
    namespace import ::stackato::jmap
    namespace import ::stackato::color
    namespace import ::stackato::mgr::alias
    rename alias manager

    namespace export aliases alias unalias
    namespace ensemble create
}

debug level  cmd/alias
debug prefix cmd/alias {[debug caller] | }

# # ## ### ##### ######## ############# #####################
## Command implementations.

proc ::stackato::cmd::alias::aliases {config} {
    debug.cmd/alias {}

    set aliases [manager known]
    #@type aliases = dict(<any>/string)

    if {[$config @json]} {
	puts [jmap aliases $aliases]
	return
    }

    if {![llength $aliases]} {
	puts "No Aliases"
	return
    }

    table::do t {Alias Command} {
	foreach {name command} $aliases {
	    $t add $name $command
	}
    }

    puts ""
    $t show puts
    return
}

proc ::stackato::cmd::alias::alias {config} {
    debug.cmd/alias {}

    set name    [$config @name]
    set command [$config @command]

    manager add $name $command
    say [color green "Successfully aliased '$name' to '$command'"]
    return
}

proc ::stackato::cmd::alias::unalias {config} {
    debug.cmd/alias {}

    set name [$config @name]

    if {![manager has $name]} {
	err [color red "Unknown alias '$name'"]
    } else {
	manager remove $name
	say [color green "Successfully unaliased '$name'"]
    }
    return
}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::cmd::alias 0
