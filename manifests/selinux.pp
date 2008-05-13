# manifests/selinux.pp

class ntp::selinux {
    case $operatingsystem {
        gentoo: { include ntp::selinux::gentoo }
        default: { info("No selinux stuff yet defined for your operatingsystem") }
    }
}

class ntp::selinux::gentoo {
    package{'selinux-ntp':
        ensure => present,
        category => 'sec-policy',
        require => Package[ntp],
    }
    selinux::loadmodule {"ntp": require => Package[selinux-ntp] }
}

