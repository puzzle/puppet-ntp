# manifests/xenu.pp

# on domU's we should set the clock to independent

class ntp::xenu {
    exec{"echo 1 > /proc/sys/xen/independent_wallclock":
        unless => "grep -q 1 /proc/sys/xen/independent_wallclock",
    }
}
