MODDIR="/data/adb/modules/system_app_nuker"
PERSIST_DIR="/data/adb/system_app_nuker"
APP_LIST="$PERSIST_DIR/app_list.json"
APP_LIST_TMP="$PERSIST_DIR/app_list.json.tmp"
REMOVE_LIST="$PERSIST_DIR/nuke_list.json"
ICON_DIR="$PERSIST_DIR/icons"

# NoMount VFS integration
NOMOUNT_SYNC_TRIGGER="/data/adb/nomount/sync_trigger"

# import config
uninstall_fallback=false
mounting_mode=0
refresh_applist=true
mount_system=magic_mount
[ -f "$PERSIST_DIR/config.sh" ] && . $PERSIST_DIR/config.sh

# === FUNCTIONS ===

# Trigger NoMount VFS sync for immediate rule update
trigger_nomount_sync() {
    if [ -d "$NOMOUNT_SYNC_TRIGGER" ]; then
        touch "$NOMOUNT_SYNC_TRIGGER/system_app_nuker" 2>/dev/null
    fi
}

# appt binary
aapt() { "$MODDIR/common/aapt" "$@"; }

# set config.sh value
set_config() {
    sed -i "s/$1=.*/$1=$2/" "$PERSIST_DIR/config.sh"
}

# validate and auto-correct mounting mode on every boot
# this ensures consistency when kernel changes (e.g., user flashes stock kernel)
validate_mounting_mode() {
    local needs_reconfig=false
    local new_mode=$mounting_mode

    # check nomount vfs availability
    nomount_available=false
    NOMOUNT_MODULE="/data/adb/modules/nomount"
    if [ -f "$NOMOUNT_MODULE/module.prop" ] && [ ! -f "$NOMOUNT_MODULE/disable" ] && [ ! -f "$NOMOUNT_MODULE/remove" ]; then
        NM_BIN="$NOMOUNT_MODULE/bin/nm"
        [ -x "$NM_BIN" ] && "$NM_BIN" ver >/dev/null 2>&1 && nomount_available=true
    fi

    # check overlayfs availability
    overlay_available=false
    grep -q "overlay" /proc/filesystems 2>/dev/null && overlay_available=true

    # check tmpfs xattr support
    tmpfs_xattr_available=false
    MNT_FOLDER=""
    [ -w /mnt ] && MNT_FOLDER=/mnt
    [ -w /mnt/vendor ] && MNT_FOLDER=/mnt/vendor
    if [ -n "$MNT_FOLDER" ]; then
        testfile="$MNT_FOLDER/tmpfs_xattr_testfile_$$"
        rm -f "$testfile" 2>/dev/null
        if busybox mknod "$testfile" c 0 0 2>/dev/null; then
            if busybox setfattr -n trusted.overlay.whiteout -v y "$testfile" 2>/dev/null; then
                tmpfs_xattr_available=true
            fi
            rm -f "$testfile" 2>/dev/null
        fi
    fi

    # check mountify module
    mountify_available=false
    if [ -f "/data/adb/modules/mountify/module.prop" ] && \
       [ ! -f "/data/adb/modules/mountify/disable" ] && \
       [ ! -f "/data/adb/modules/mountify/remove" ]; then
        mountify_mounts=$(grep -o 'mountify_mounts=[0-9]' /data/adb/mountify/config.sh 2>/dev/null | cut -d= -f2)
        if [ "$mountify_mounts" = "2" ] || \
           { [ "$mountify_mounts" = "1" ] && grep -q "system_app_nuker" /data/adb/mountify/modules.txt 2>/dev/null; }; then
            mountify_available=true
        fi
    fi

    # CASE 1: VFS mode but kernel support missing
    if [ "$mounting_mode" = "3" ] && [ "$nomount_available" = false ]; then
        echo "app_nuker: VFS mode configured but kernel support missing" >> /dev/kmsg
        echo "app_nuker: Auto-fallback to next available mode..." >> /dev/kmsg
        needs_reconfig=true

        # find next best mode
        if [ "$mountify_available" = true ]; then
            new_mode=2
        elif [ "$overlay_available" = true ] && [ "$tmpfs_xattr_available" = true ]; then
            new_mode=1
        else
            new_mode=0
        fi
    fi

    # --- CASE 2: VFS available but not being used (auto-upgrade) ---
    if [ "$nomount_available" = true ] && [ "$mounting_mode" != "3" ]; then
        echo "app_nuker: NoMount VFS detected - auto-upgrading to VFS mode!" >> /dev/kmsg
        needs_reconfig=true
        new_mode=3
    fi

    # --- CASE 3: Mountify configured but not available ---
    if [ "$mounting_mode" = "2" ] && [ "$mountify_available" = false ] && [ "$nomount_available" = false ]; then
        echo "app_nuker: WARNING - Mountify mode configured but not available!" >> /dev/kmsg
        needs_reconfig=true
        if [ "$overlay_available" = true ] && [ "$tmpfs_xattr_available" = true ]; then
            new_mode=1
        else
            new_mode=0
        fi
    fi

    # --- CASE 4: Standalone mode but requirements not met ---
    if [ "$mounting_mode" = "1" ] && [ "$nomount_available" = false ]; then
        if [ "$overlay_available" = false ] || [ "$tmpfs_xattr_available" = false ]; then
            echo "app_nuker: WARNING - Standalone mode requirements not met!" >> /dev/kmsg
            needs_reconfig=true
            new_mode=0
        fi
    fi

    # apply reconfiguration if needed
    if [ "$needs_reconfig" = true ]; then
        echo "app_nuker: Changing mounting_mode from $mounting_mode to $new_mode" >> /dev/kmsg
        mounting_mode=$new_mode
        set_config mounting_mode $new_mode

        # update mount_system based on new mode
        if [ "$new_mode" = "3" ]; then
            mount_system=vfs_nomount
        elif [ "$new_mode" = "2" ] || [ "$new_mode" = "1" ]; then
            mount_system=overlayfs
        else
            mount_system=magic_mount
        fi
        set_config mount_system $mount_system
        echo "app_nuker: mount_system set to $mount_system" >> /dev/kmsg

        # update skip_mount based on new mode
        if [ "$new_mode" = "3" ] || [ "$new_mode" = "1" ]; then
            touch "$MODDIR/skip_mount"
            touch "$MODDIR/skip_mountify"
        elif [ "$new_mode" = "0" ]; then
            rm -f "$MODDIR/skip_mount"
            rm -f "$MODDIR/skip_mountify"
        fi
    fi
}

# update module description
update_description() {
    status="$1"
    
    if [ -z "$string" ]; then # if not exist yet
        # base description
        string="WebUI-based debloater and whiteout creator"
        
        # count nuked apps (fallback to 0 if file missing or grep fails)
        total=0
        if [ -f "$REMOVE_LIST" ]; then
            total=$(grep -c '"package_name":' "$REMOVE_LIST" 2>/dev/null)
            if [ $? -ne 0 ]; then
                total=0
            fi
        fi
        
        # fallback if grep somehow returns blank
        if [ -z "$total" ]; then
            total=0
        fi
        
        # pluralize
        suffix=""
        if [ "$total" -ne 1 ]; then
            suffix="s"
        fi
        
        # add nuked app count
        string="$string | 💥 nuked: $total app$suffix"
        
        # detect and validate mount mode
        if [ "$mounting_mode" = "3" ]; then
            if [ "$nomount_available" = "true" ]; then
                string="$string | ⚡ mount mode: nomount vfs (undetectable)"
            else
                string="[ERROR] VFS mode configured but kernel support missing"
            fi
        elif [ "$mounting_mode" = "0" ]; then
            string="$string | ⚙️ mount mode: default"
            if [ "$magic_mount" = "true" ]; then
                # check if manager mount is disabled
                if { [ "$KSU_NEXT" = "true" ] && [ "$KSU_VER_CODE" -lt 22098 ] && [ -f "/data/adb/ksu/.nomount" ]; } || \
                    { [ "$APATCH" = "true" ] && [ -f "/data/adb/ap/.litemode_enable" ]; }; then
                    string="[ERROR] .nomount or .litemode_enable on magic mount"
                fi
            fi
        elif [ "$mounting_mode" = "1" ]; then
            # check if tmpfs xattrs is available (only required when magic_mount is true)
            if [ "$magic_mount" = "true" ]; then
                MNT_FOLDER=""
                [ -w /mnt ] && MNT_FOLDER=/mnt
                [ -w /mnt/vendor ] && MNT_FOLDER=/mnt/vendor
                testfile="$MNT_FOLDER/tmpfs_xattr_testfile"
                rm $testfile > /dev/null 2>&1
                busybox mknod "$testfile" c 0 0 > /dev/null 2>&1
                if busybox setfattr -n trusted.overlay.whiteout -v y "$testfile" > /dev/null 2>&1 ; then
                    rm $testfile > /dev/null 2>&1
                    string="$string | 🧰 mount mode: mountify standalone script"
                else
                    rm $testfile > /dev/null 2>&1
                    string="[ERROR] mountify standalone mode requires tmpfs xattr support or overlayfs manager"
                fi
            else
                string="$string | 🧰 mount mode: mountify standalone script (overlayfs)"
            fi
        elif [ "$mounting_mode" = "2" ]; then
            if [ -f "/data/adb/modules/mountify/config.sh" ] && \
            [ ! -f "/data/adb/modules/mountify/disable" ] && \
            [ ! -f "/data/adb/modules/mountify/remove" ]; then
                mountify_mounts=$(grep -o 'mountify_mounts=[0-9]' /data/adb/modules/mountify/config.sh | cut -d= -f2)

                # if mountify module will mount this module
                if [ "$mountify_mounts" = "2" ] || \
                { [ "$mountify_mounts" = "1" ] && grep -q "system_app_nuker" /data/adb/modules/mountify/modules.txt; }; then
                    mountify_mounted=true
                    echo "[✓] Mounting will be handled by the mountify module."
                    mounting_mode=2
                    # set_config mounting_mode 2
                    string="$string | 🧰 mount mode: mountify module"
                else
                    string="[ERROR] mountify module mode is enabled but module won't mount this (check if mountify is enabled and this module is on the modules.txt)"
                fi
            fi
        fi
    fi
    
    # add status if provided
    if [ -n "$status" ]; then
        string="$string | $status"
    fi
    
    # set module description - escape special characters for sed
    escaped_string=$(echo "description=$string" | sed 's/[[\.*^$()+?{|]/\\&/g')
    sed -i "s/^description=.*/$escaped_string/g" "$MODDIR/module.prop"
}

# create applist cache
create_applist() {
    # Update description to show loading status
    update_description "📱 loading app list..."
    
    echo "[" > "$APP_LIST_TMP"

    # default system app path
    system_app_path="/system/app /system/priv-app /vendor/app /product/app /product/priv-app /system_ext/app /system_ext/priv-app"

    # append additional partition on mountify or vfs mode
    if [ "$mounting_mode" = "1" ] || [ "$mounting_mode" = "2" ] || [ "$mounting_mode" = "3" ]; then
        system_app_path="$system_app_path my_bigball mi_ext my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_reserve my_stock"
    fi
    for path in $system_app_path; do
        find "$path" -maxdepth 2 -type f -name "*.apk" | while read APK_PATH; do
            # skip if already on app list
            if grep -q "$APK_PATH" "$APP_LIST_TMP"; then
                continue
            fi
            
            # skip if path is in nuke list
            if echo "$NUKED_PATHS" | grep -q "$APK_PATH"; then
                continue
            fi

            [ -z "$PKG_LIST" ] && PKG_LIST=$(pm list packages -f)
            PACKAGE_NAME=$(echo "$PKG_LIST" | grep "$APK_PATH" | awk -F= '{print $2}')
            [ -z "$PACKAGE_NAME" ] && PACKAGE_NAME=$(aapt dump badging "$APK_PATH" 2>/dev/null | grep "package:" | awk -F' ' '{print $2}' | sed "s/^name='\([^']*\)'.*/\1/")
            [ -z "$PACKAGE_NAME" ] && continue

            APP_NAME=$(aapt dump badging "$APK_PATH" 2>/dev/null | grep "application-label:" | sed "s/application-label://g; s/'//g")
            [ -z "$APP_NAME" ] && APP_NAME="$PACKAGE_NAME"

            echo "  {\"app_name\": \"$APP_NAME\", \"package_name\": \"$PACKAGE_NAME\", \"app_path\": \"$APK_PATH\"}," >> "$APP_LIST_TMP"
            
            ICON_PATH=$(aapt dump badging "$APK_PATH" 2>/dev/null | grep "application:" | awk -F "icon=" '{print $2}' | sed "s/'//g")
            # Extract the icon if it exists
            ICON_FILE="$ICON_DIR/$PACKAGE_NAME.png"

            if [ -n "$ICON_PATH" ]; then
                [ ! -f "$ICON_FILE" ] && unzip -p "$APK_PATH" "$ICON_PATH" > "$ICON_FILE"
            fi
        done
    done

    # Fallback for no package name found
    for package_name in $(pm list packages -s | sed 's/package://g'); do
        if grep -q "\"$package_name\"" "$APP_LIST_TMP"; then
            continue
        fi
        APP_NAME=$(aapt dump badging "$package_name" 2>/dev/null | grep "application-label:" | sed "s/application-label://g; s/'//g")
        [ -z "$APP_NAME" ] && APP_NAME="$package_name"

        APK_PATH=$(pm path $package_name | sed 's/package://g')
        echo "$APK_PATH" | grep -qE "/system/app|/system/priv-app|/vendor/app|/product/app|/product/priv-app|/system_ext/app|/system_ext/priv-app" || continue
        echo "  {\"app_name\": \"$APP_NAME\", \"package_name\": \"$package_name\", \"app_path\": \"$APK_PATH\"}, " >> "$APP_LIST_TMP"
    done

    sed -i '$ s/,$//' "$APP_LIST_TMP"
    echo "]" >> "$APP_LIST_TMP"

    mv -f "$APP_LIST_TMP" "$APP_LIST"
    
    # Update description to show loaded status
    update_description "✅ app list loaded"
}

# === MAIN SCRIPT ===

# wait for boot completed
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

# -- validate mounting mode on every boot --
# this auto-corrects config if kernel changed (e.g., VFS removed/added)
validate_mounting_mode

# -- set module description --
# set initial description (after validation so it shows correct mode)
update_description

# make sure persist dir exist
[ ! -d "$PERSIST_DIR" ] && mkdir -p "$PERSIST_DIR"

# reset bootcount
echo "BOOTCOUNT=0" > "$PERSIST_DIR/count.sh"
chmod 755 "$PERSIST_DIR/count.sh"

# ensure the remove list exists
[ -s "$REMOVE_LIST" ] || echo "[]" > "$REMOVE_LIST"

# get list of app paths to be removed
NUKED_PATHS=$(grep -o "\"app_path\":.*" "$REMOVE_LIST" | awk -F"\"" '{print $4}')
# ensure the icon directory exists
[ ! -d "$ICON_DIR" ] && mkdir -p "$ICON_DIR"

# create or refresh app list
if [ ! -f "$APP_LIST" ] || [ "$refresh_applist" = true ]; then
    create_applist
else
    # Update description to indicate app list won't be reloaded
    update_description "📋 no reload applist"
fi

# create symlink for app icon
rm -rf "$MODDIR/webroot/link" && ln -s $PERSIST_DIR $MODDIR/webroot/link

# this make sure that restored app is back
restored_any=false
for pkg in $(grep -o "\"package_name\":.*" "$APP_LIST" | awk -F"\"" '{print $4}'); do
    if ! pm path "$pkg" >/dev/null 2>&1; then
        pm install-existing "$pkg" >/dev/null 2>&1
        restored_any=true
    fi
    disabled_list=$(pm list packages -d)
    if echo "$disabled_list" | grep -qx "package:$pkg"; then
        pm enable "$pkg" >/dev/null 2>&1 || true
        restored_any=true
    fi
done

# Trigger NoMount sync if any apps were restored
# This ensures stale VFS rules are cleaned up immediately
[ "$restored_any" = true ] && trigger_nomount_sync

# uninstall fallback if apps aint nuked at late service
# enable this on config.sh
$uninstall_fallback && {
    # remove system apps if they still exist
    for package_name in $(grep -o "\"package_name\":.*" "$REMOVE_LIST" | awk -F"\"" '{print $4}'); do
        if pm list packages | grep -qx "package:$package_name"; then
            pm uninstall -k --user 0 "$package_name" 2>/dev/null
        fi
    done
}

# EOF
