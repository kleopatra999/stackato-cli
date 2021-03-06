# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file doc/license.txt for the license terms.

# # ## ### ##### ######## ############# #####################

package require Tcl 8.5
package require try            ;# I want try/catch/finally
package require dictutil
package require fileutil::traverse
package require cd
package require zipfile::decode
package require stackato::mgr::manifest
package require stackato::mgr::framework::base
package require stackato::mgr::framework::sabase
package require stackato::mgr::framework::standalone

namespace eval ::stackato::mgr {
    namespace export framework
    namespace ensemble create
}

namespace eval ::stackato::mgr::framework {
    namespace export \
	known lookup detect create \
	defaultmem defaultframe
    namespace ensemble create

    namespace import ::stackato::mgr::manifest
}

debug level  mgr/framework
debug prefix mgr/framework {[debug caller] | }

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::framework::defaultmem {} {
    variable default_mem
    return  $default_mem
}

proc ::stackato::mgr::framework::defaultframe {} {
    variable default_frame
    return  $default_frame
}

proc ::stackato::mgr::framework::known {supported} {
    debug.mgr/framework {}

    variable known
    variable frameworks
    variable fbyid

    debug.mgr/framework { known     = $known}
    debug.mgr/framework { supported = $supported}

    # Filter out the frameworks not supported by the current target.
    set res {}
    foreach k $known {
	# Pull the actual id out of the data structure, because
	# that is what 'supported' contains. Whereas 'known' is
	# the list of user readable names.
	set id [lindex [dict get $frameworks $k] 0]
	if {![dict exists $supported $id]} continue
	lappend res $k
    }

    # Add in the frameworks supported by the server, but not the
    # client, these will cause the client to ask later about the
    # memory requirements.

    foreach {s _} $supported {
	if {[dict exist $fbyid $s]} continue
	lappend res $s
    }
    return $res
}

proc ::stackato::mgr::framework::lookup {name} {
    debug.mgr/framework {}

    variable frameworks
    try {
	set spec [dict get $frameworks $name]
	set name [lindex $spec 0]
    } on error {e o} {
	# We don't know anything about the framework which
	# was detected or chosen. The higher levels will
	# handle the situation.
	return {}
    }

    debug.mgr/framework {name = $name}
    debug.mgr/framework {spec = $spec}

    return [create $name {*}$spec]
}

proc ::stackato::mgr::framework::detect {path {available {}}} {
    debug.mgr/framework {}

    if {![file exists   $path]} { return {} }
    if {![file readable $path]} { return {} }

    if {[file isdirectory $path]} {
	return [detect_from_dir $path $available]
    } elseif {[file extension $path] eq ".war"} {
	return [detect_framework_from_war $path]
    } elseif {[file extension $path] eq ".zip"} {
	return [detect_framework_from_zip $path $available]
    } elseif {"standalone" in $available} {
	return [lookup Standalone]
    } else {
	return {}
    }
}

proc ::stackato::mgr::framework::detect_from_dir {path {available {}}} {
    debug.mgr/framework {}

    cd::indir $path {
	debug.mgr/framework {CWD = [pwd]}

	# Special test for Heroku Buildpack, stackato.yml) ...
	if {[dict exists [manifest env] BUILDPACK_URL]} {
	    debug.mgr/framework  Heroku/Buildpack/BUILDPACK_URL
	    return [lookup {Heroku Buildpack}]
	}

	# Buildpack: Play!
	set bp 0
	fileutil::traverse T .
	T foreach p {
	    if {![string match "*/conf/application.conf" $p]} continue
	    if {[string match "*modules*" $p]} continue
	    if {![file isfile $p]} continue
	    # application.conf, a file, not under a modules directory.
	    set bp 1
	    break
	}
	T destroy
	if {$bp} {
	    debug.mgr/framework Heroku/Buildpack/regular
	    return [lookup {Heroku Buildpack}]
	}

	# Buildpack: Go
	set bp 0
	fileutil::traverse T .
	T foreach p {
	    if {![string match "*.go" $p]} continue
	    if {![file isfile $p]} continue
	    # *.go under any directory
	    set bp 1
	    break
	}
	T destroy
	if {$bp} {
	    debug.mgr/framework Heroku/Buildpack/regular
	    return [lookup {Heroku Buildpack}]
	}

	# Buildpack: Clojure!
	if {[file exists project.clj]} {
	    return [lookup {Heroku Buildpack}]
	}

	# Rails
	if {[file exists config/environment.rb]} {
	    debug.mgr/framework Rails
	    return [lookup Rails]
	}

	# Rack
	if {[file exists config.ru]} {
	    debug.mgr/framework Rack
	    return [lookup Rack]
	}

	# Java
	if {[llength [glob -nocomplain *.ear]]} {
	    # Old JEE packaging
	    return [lookup JavaEE]
	}
	if {[set warfile [lindex [glob -nocomplain *.war] 0]] ne {}} {
	    debug.mgr/framework Java/War
	    debug.mgr/framework {[package ifneeded zipfile::decode [package present zipfile::decode]]}

	    if {[file isdirectory $warfile]} {
		# Recurse. Note how our .war file is actually a directory.
		return [detect_from_dir $warfile $available]
	    } else {
		return [detect_framework_from_war $warfile]
	    }
	}
	if {[file exists WEB-INF/web.xml]} {
	    # Unpacked war file ...
	    return [detect_framework_from_war]
	}

	# Simple Ruby Apps
	if {[llength [set rb [glob -nocomplain *.rb]]]} {
	    set matched_file {}

	    foreach fname $rb {
		#@todo @note sinatra check, should extend fileutil::type.
		set c [open $fname]
		set str [read $c 1024]
		close $c

		if {$str eq {}} continue
		if {![regexp {\s*require[\s(]*['"]sinatra['"]} $str]} \
		    continue

		set matched_file $fname
	        break
	    }

	    if {$matched_file ne {}} {
		set f [lookup Sinatra]
		if {$f ne {}} {
		    $f exec "ruby $matched_file"
		}
		return $f
	    }
	}

	# Perl
	if {[file exists app.psgi]} {
	    return [lookup Perl]
	}

	# Node.js
	if {[llength [glob -nocomplain *.js]]} {
	    # Fixme, make other files work too..

	    foreach f {
		server.js app.js index.js main.js
	    } {
		if {![file exists $f]} continue
		return [lookup Node]
	    }
	}

	# PHP
	if {[llength [glob -nocomplain *.php]]} {
	    return [lookup PHP]
	}

	# ASP.NET
	if {[llength [glob -nocomplain web.config]] ||
	    [llength [glob -nocomplain *.aspx]]} {
	    if {"aspdotnet" in $available} {
		return [lookup ASPDotNet]
	    } else {
		return [lookup ASPNet]
	    }
	}

	# Erlang/OTP using Rebar
	if {[llength [glob -nocomplain releases/*/*.rel]] ||
	    [llength [glob -nocomplain releases/*/*.boot]]} {
	    return [lookup {Erlang/OTP Rebar}]
	}

	# Python
	if {[file exists wsgi.py]} {
	    return [lookup Python]
	}

    } ; # Cd::indir

    if {"standalone" in $available} {
	return [lookup Standalone]
    }

    return {}
}

proc ::stackato::mgr::framework::detect_framework_from_war {{warfile {}}} {
    if {$warfile ne {}} {
	set contents [zipfile::decode::content $warfile]
    } else {
	fileutil::traverse T .
	set contents [T files]
	T destroy
    }

    if {[lsearch -glob $contents {WEB-INF/lib/grails-web-*.jar}] >= 0} {
	return [lookup Grails]
    }
    if {[lsearch -glob $contents {WEB-INF/lib/lift-webkit*.jar}] >= 0} {
	return [lookup Lift]
    }
    if {[lsearch -exact $contents {WEB-INF/classes/org/springframework}] >= 0} {
	return [lookup Spring]
    }
    if {[lsearch -glob $contents {WEB-INF/lib/spring-core*.jar}] >= 0} {
	return [lookup Spring]
    }
    if {[lsearch -glob $contents {WEB-INF/lib/org.springframework.core*.jar}] >= 0} {
	return [lookup Spring]
    }
    if {[lsearch -exact $contents {WEB-INF/classes/META-INF/persistence.xml}] >= 0} {
	return [lookup JavaEE]
    }
    return [lookup JavaWeb]
}

proc ::stackato::mgr::framework::detect_framework_from_zip {zipfile {available {}}} {
    debug.mgr/framework {}
    return [detect_framework_from_zip_contents \
		[zipfile::decode::content $zipfile] \
		$available]
}

proc ::stackato::mgr::framework::detect_framework_from_zip_contents {contents {available {}}} {
    debug.mgr/framework {}
    # play not supported by us !? (not in our list below), disabled
    if {0 &&("play" in $available) &&
	([lsearch -regexp $contents {lib/play\..*\.jar}] >= 0)} {
	lookup Play
    }
    if {"standalone" in $available} {
	lookup Standalone
    }
    return {}
}

# # ## ### ##### ######## ############# #####################

proc ::stackato::mgr::framework::create {args} {
    debug.mgr/framework {}

    if {[lindex $args 0] eq "standalone"} {
	set class standalone
    } elseif {[manifest standalone]} {
	set class sabase
    } else {
	set class base
    }

    debug.mgr/framework {class = $class}
    return [$class new {*}$args]
}

# # ## ### ##### ######## ############# #####################

namespace eval ::stackato::mgr::framework {
    variable frameworks {
	ASPNet             {aspnet     { mem 512M description {.NET Web Application} }}
	ASPDotNet          {aspdotnet  { mem 512M description {IronFoundry .NET Web Application} }}
	Generic            {generic    { mem 256M description {Generic Application} }}
	Grails  	   {grails     { mem 512M description {Java SpringSource Grails Application} }}
	JavaEE  	   {java_ee    { mem 512M description {Java EE Application} }}
	JavaWeb 	   {java_web   { mem 512M description {Java Web Application} }}
	Lift	  	   {lift       { mem 512M description {Scala Lift Application} }}
	Node               {node       { mem 128M description {Node.js Application} }}
	PHP                {php        { mem 128M description {PHP Application}}}
	Perl               {perl       { mem 128M description {Perl PSGI Application} }}
	Python             {python     { mem 128M description {Python Application} }}
	Rack               {rack       { mem 128M description {Rack application} }}
	Rails   	   {rails3     { mem 128M description {Rails Application} }}
	Roo     	   {spring     { mem 512M description {Java SpringSource Roo Application} }}
	Sinatra 	   {sinatra    { mem 128M description {Sinatra Application} }}
	Spring  	   {spring     { mem 512M description {Java SpringSource Spring Application} }}
	Standalone         {standalone { mem 64M description {Standalone application} }}
	{Erlang/OTP Rebar} {otp_rebar  { mem 128M description {Erlang/OTP Rebar Application} }}
	{Heroku Buildpack} {buildpack  { mem 256M description {Heroku Buildpack-based Application} }}
     }

    variable default_mem   256M
    variable default_frame http://b20nine.com/unknown

    namespace export known lookup detect create
    namespace ensemble create
}

::apply {{} {
    variable known {}
    variable frameworks
    variable fbyid

    # frameworks = dict (key -> spec)
    # spec       = list (name, dict (mem, description))

    # Generate lower-case aliases, rewrite all entries to save their
    # actual key in them, and collate the list of user visible keys.
    dict for {k v} $frameworks {
	lappend known $k

	lassign $v name spec
	dict set fbyid $name $spec
	dict set spec key $k
	set v [list $name $spec]

	dict set frameworks $k                  $v
	dict set frameworks [string tolower $k] $v

	if {[dict exists $frameworks $name]} continue
	dict set frameworks $name               $v
    }

    # frameworks = dict (key -> spec)
    # spec       = list (name, dict (key, mem, description))

    # fbykey = dict (name -> dict (mem, description))

} ::stackato::mgr::framework}

# # ## ### ##### ######## ############# #####################
## Ready
package provide stackato::mgr::framework 0
