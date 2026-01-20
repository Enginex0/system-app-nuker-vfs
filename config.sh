# uninstall fallback if app ain't nuked on late service
# this runs: pm uninstall -k --user 0
# only triggers if the app still exists after late-service
# default is false
uninstall_fallback=false

# disable only mode
# if this is enabled, whiteouts for apps would not be created
disable_only_mode=false

# --- mounting mode ---
# 0 = default; manager will handle this module's mounting
# 1 = mountify standalone script; this module will be mounted using mountify standalone script thats shipped with this module
# 2 = mountify module; the mountify module will handle this module's mounting
# 3 = nomount vfs; kernel VFS-level hiding (undetectable)
# mountify standalone script needs either **TMPFS_XATTR** support or the OverlayFS manager
# nomount vfs requires a kernel with CONFIG_NOMOUNT=y compiled in
# DO NOT flip this manually unless you're sure the env supports it
# priority order: 3 (vfs) > 2 (mountify) > 1 (standalone) > 0 (default)
mounting_mode=0

# refresh (regenerate) the app list cache every boot
# default is true to make sure app list stays accurate when things change
refresh_applist=true

# ----
# ⚠️ DO NOT EDIT BELOW THIS LINE
# config(s) below are env-specific or not meant to be touched
# these are auto-set and might break stuff if changed manually
# ----

# detected mount system (auto-set based on what's available)
# values: vfs_nomount, overlayfs, magic_mount
mount_system=magic_mount

# EOF
