#
# ntp module
# ntp/manifests/init.pp - Classes for configuring NTP
#
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# Copyright 2008, admin(at)immerda.ch
# Copyright 2008, Puzzle ITC GmbH
# Marcel Härry haerry+puppet(at)puzzle.ch
# Simon Josi josi+puppet(at)puzzle.ch
#
# This program is free software; you can redistribute 
# it and/or modify it under the terms of the GNU 
# General Public License version 3 as published by 
# the Free Software Foundation.
#

modules_dir { "ntp": }
	
$ntp_base_dir = "/var/lib/puppet/modules/ntp"

class ntp {
    case $kernel {
        linux: {
            case $operatingsystem {
                debian: { include ntp::debian }
                gentoo: { include ntp::gentoo }
                default: { include ntp::linux }
            }
        }
        openbsd: { include ntp::openbsd }
        default: { fail("no classes for this kernel yet defined!") }
    }    

    if $selinux {
        include ntp::selinux
    }

    case $virtual {
        'xenu': { include ntp::xenu }
    }
}
class ntp::base {

	package { ntp:
	    ensure => installed,
		before => File["/etc/ntp.conf"],
	}

    file {"/var/lib/puppet/modules/ntp":
        ensure => directory,
        force => true,
        mode => 0755, owner => root, group => 0;
    }

	$local_stratum = $ntp_local_stratum ? {
		'' => 13,
		default => $ntp_local_stratum,
	}

	config_file { "/etc/ntp.conf":
		content => template("ntp/ntp.conf"),
		require => Package[ntp],
	}

    service{ntpd:
        ensure => running,
        subscribe => [ File["/etc/ntp.conf"], File["/etc/ntp.client.conf"], File["/etc/ntp.server.conf"] ],
    }
	
    if $use_munin {
        # various files and directories used by this module
	    file{"${ntp_base_dir}/munin_plugin":
			source => "puppet://$server/ntp/ntp_",
			mode => 0755, owner => root, group => 0;
	    }

	    $ntps = gsub(split($configured_ntp_servers, " "), "(.+)", "ntp_\\1")

	    munin::plugin { $ntps:
		    ensure => "munin_plugin",
		    script_path_in => $ntp_base_dir
	    }
    }
	case $ntp_servers { 
		'': { include ntp::client }
		default: { include ntp::server }
	}

	# collect all our configs
	File <<| tag == 'ntp' |>>


	# private
	# Installs a munin plugin and configures it for a given host
	define munin_plugin() {

		$name_with_underscores = gsub($name, "\\.", "_")

		# replace the "legacy" munin plugin with our own
		munin::plugin {
			"ntp_${name_with_underscores}": ensure => absent;
			"ntp_${name}":
				ensure => "munin_plugin",
				script_path => "/var/lib/puppet/modules/ntp"
				;
		}
	}
}

define ntp::upstream_server($server_options = 'iburst') {
    ntp::add_config { "server_${name}":
	    content => "server ${name} ${server_options}",
		type => "server",
	}
	# This will need the ability to collect exported defines
	# currently this is worked around by reading /etc/ntp*conf via a fact
	# case $name { $fqdn: { debug ("${fqdn}: Ignoring get_time_from for self") } default: { munin_ntp { $name: } } }
}
define ntp::add_config($content, $type) {
    config_file { "/var/lib/puppet/modules/ntp/ntp.${type}.d/${name}":
	    content => "$content\n",
		before => File["/etc/ntp.${type}.conf"],
	}

}

# this is a server, connect to the specified upstreams
class ntp::server {
	info ( "${fqdn} will act as ntp server using ${ntp_servers} as upstream" )
	ntp::upstream_server { $ntp_servers: }
    # export this server for our own clients
	@@concatenated_file_part {
        "server_${fqdn}":
	        dir => "/var/lib/puppet/modules/ntp/ntp.client.d",
		    content => "server ${fqdn} iburst\n",
		    tag => 'ntp',
		    ## TODO: activate this dependency when the bug is fixed
		    #before => File["/etc/ntp.client.conf"]
		    ;
		# export this server for our other servers
		"peer_${fqdn}":
		    dir => "/var/lib/puppet/modules/ntp/ntp.server.d",
			content => "peer ${fqdn} iburst\nrestrict ${fqdn} nomodify notrap\n",
			tag => 'ntp',
			## TODO: activate this dependency when the bug is fixed
			#before => File["/etc/ntp.server.conf"]
			;
	}
	concatenated_file {"/etc/ntp.server.conf":
	    dir => "/var/lib/puppet/modules/ntp/ntp.server.d",
	}
	file { "/var/lib/puppet/modules/ntp/ntp.client.d": ensure => directory, }
	# provide dummy dependency for collected files
	exec { "concat_/var/lib/puppet/modules/ntp/ntp.client.d":
	    command => "true",
		refreshonly => true,
	}
	config_file { "/etc/ntp.client.conf": content => "\n", }

    if $use_nagios {
	    include nagios::service::ntp 
    }
}

# this is a client, connect to our own servers
class ntp::client {
    info ( "${fqdn} will act as ntp client" )
    # collect all our servers
    concatenated_file { "/etc/ntp.client.conf":
        dir => "/var/lib/puppet/modules/ntp/ntp.client.d",
    }

    # unused configs
    file { "/var/lib/puppet/modules/ntp/ntp.server.d": ensure => directory, }
    # provide dummy dependency for collected files
    exec { "concat_/var/lib/puppet/modules/ntp/ntp.server.d":
        command => "true",
        refreshonly => true,
    }
    config_file { "/etc/ntp.server.conf": content => "\n", }
}

class ntp::linux inherits ntp::base {
    Service[ntpd]{
        enable => true,
    }
}
class ntp::gentoo inherits ntp::linux {
    Package[ntp]{
        category => 'net-misc',
    }
}

class ntp::debian inherits ntp::linux {
    case $lsbdistcodename {
        'sarge': { 
            Package[ntp]{
                name => 'ntp-server', 
            }
        }
    }
    Service['ntpd']{
        name => 'ntp',
    }
}

class ntp::openbsd inherits ntp::base {
    Package[ntp]{
	    source => 'ftp://mirror.switch.ch/pub/OpenBSD/4.2/packages/i386/ntp-4.2.0ap3.tgz',
    }
    Service[ntpd]{
        binary =>  "/usr/sbin/ntpd",
        provider => base,
        pattern => ntpd,
    }
 
}

# include this class on hosts who collect files but do not have other ntp infrastructure
class ntp::none {
	exec {
		"concat_/var/lib/puppet/modules/ntp/ntp.client.d":
			command => "true",
			refreshonly => true;
		"concat_/var/lib/puppet/modules/ntp/ntp.server.d":
			command => "true",
			refreshonly => true,
	}
	# also provide dummy directories!
	modules_dir { ["ntp/ntp.server.d", "ntp/ntp.client.d"]: }
}
