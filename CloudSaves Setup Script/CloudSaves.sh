#!/bin/bash
# created by eric5949 (eric5949@outlook.com)
# i did this manually for a couple years and finally got tired of it. this should make things easier for me and if you can make use of it then great.

source "$HOME/bin/ncsync.env"  # we do need these if they exist already for some functions.
logcheck() { # check if this script has created its log in the NCSOURCE folder
    echo "starting ${FUNCNAME[0]}"
    NCDEST=$(echo "$NCFOLDERS" | cut -d: -f1)
    if [ -f "$NCDEST/csgames.txt" ]; then
        whattolink
    else
        cloud_selector
    fi
}
cloud_selector() { # basically a dummy function right now. the script is created to support nextcloud, if someone wants to edit it to work with something else I certainly woudln't want to make their job harder.
    echo "starting ${FUNCNAME[0]}"
    CLOUD="nextcloud"
    if [ "$CLOUD" == "nextcloud" ]; then
        ncservice_check
    elif [ "$CLOUD" == "ocis" ]; then # i did swap to owncloud infinte scale at one point and adapting the whole thing to ocis was not hard.
        ocisservice_check
    else
        zenity --info --title="Something's busted..." --text="yeah so this should never appeaar and if it did well the guy who wrote this made a mistake.  You should let him know, assuming you're not him."
    fi
}
ncservice_check() { # Check if the ncsync service exists already.
    echo "exiting ${FUNCNAME[0]}"
    if systemctl --user list-units --type=service --all | grep -q "ncsync.service"; then
        ncservice_exist
    else
        ncservice_missing
    fi
}
ncservice_exist() { # The ncsync service already exists.
    echo "starting ${FUNCNAME[0]}"
    if [ "$UPDATE" = "TRUE " ];  then
    ncenv_creation
    else
    CHOICE=$(zenity --list --title="What to do?" --column="Options" \ "Service exists, what to do?" \
    "Update Service" "Sync Saves" --height=600 )
    echo "CHOICE selected: $CHOICE"
    fi
    if [ "$CHOICE" = "Update Service" ]; then
        ncenv_creation
    elif [ "$CHOICE" = "Sync Saves" ]; then
        UPDATE= "TRUE"
        definition_seleciton
    fi
}
ncservice_missing() { # The ncsync service does not exist. inform the user, create directories, and install nextcloud flatpak if it isnt already.
    echo "starting ${FUNCNAME[0]}"
    zenity --info --text="This tool uses the nextcloud flatpak to sync a predefined cloudsaves folder with a folder on your nextcloud instance and automatically handles linking folders where they need to be so your saves can sync between computers. " --width=600
    mkdir -p "$HOME/bin"
    mkdir -p "$HOME/.config/systemd/user/"

    if flatpak list | grep -q "com.nextcloud.desktopclient.nextcloud"; then
        true
    else
        zenity --info --text="Nextcloud Flatpak is not installed. Installing now..."
        flatpak install --user -y flathub com.nextcloud.desktopclient.nextcloud
    fi
    ncenv_creation
}
ncenv_creation () { # create the ncsync.env file
    echo "starting ${FUNCNAME[0]}"
    VALUES=$(zenity --forms --title="Nextcloud Configuration" --text="" --width=600 \
        --add-entry="Nextcloud Server URL" \
        --add-entry="Nextcloud User" \
        --add-password="Nextcloud Password" \
        --add-entry="Local Folder" \
        --add-entry="Remote Folder" \
        --separator="|")

    NCSERV=$(echo "$VALUES" | cut -d '|' -f1)
    NCUSER=$(echo "$VALUES" | cut -d '|' -f2)
    NCPASS=$(echo "$VALUES" | cut -d '|' -f3)
    NCFOLDERS="$(echo "$VALUES" | cut -d'|' -f4):$(echo "$VALUES" | cut -d'|' -f5)"
        cat <<EOF > "$HOME/bin/ncsync.env"
NCSERV="$NCSERV"
NCUSER="$NCUSER"
NCPASS="$NCPASS"
NCFOLDERS=("$NCFOLDERS")
EOF
    create_ncservice
}
create_ncservice() { # Create and start the ncsync service, script and timer.
    echo "starting ${FUNCNAME[0]}"
    cat <<'EOF' > $HOME/bin/ncsync.sh
#!/bin/bash

source "$HOME/bin/ncsync.env"

NCCMD="flatpak run --command=/app/bin/nextcloudcmd com.nextcloud.desktopclient.nextcloud"

if pgrep nextcloudcmd; then
    true    # skip this run if a sync is already ongoing
else

    for ENTRY in "${NCFOLDERS[@]}"; do
        NCDEST=$(echo "$ENTRY" | cut -d: -f1)
        NCSOURCE=$(echo "$ENTRY" | cut -d: -f2)
        $NCCMD --user "$NCUSER" --password "$NCPASS" --path "/$NCSOURCE" "$NCDEST"   "https://$NCSERV" 2>> "$HOME/ncsync.log"
    done

fi

exit 0
EOF
    chmod +x "$HOME/bin/ncsync.sh"
    cat <<EOF > $HOME/.config/systemd/user/ncsync.service
[Unit]
Description=Nextcloud synchronization
Wants=ncsync.timer

[Service]
WorkingDirectory=%h/bin
EnvironmentFile=%h/bin/ncsync.env
Type=oneshot
ExecStart=%h/bin/ncsync.sh

[Install]
WantedBy=default.target
EOF
    cat <<EOF > $HOME/.config/systemd/user/ncsync.timer
[Unit]
Description=Nextcloud synchronization
Requires=ncsync.service

[Timer]
Unit=ncsync.service
Persistent=true
OnActiveSec=1m
OnUnitInactiveSec=5m

[Install]
WantedBy=timers.target
EOF
    NCDEST=$(echo "$NCFOLDERS" | cut -d: -f1)
    if [ "$UPDATE" = "TRUE " ];  then
    mkdir -p "$NCDEST"
    systemctl --user stop ncsync.service ncsync.timer
    systemctl --user disable ncsync.service ncsync.timer
    systemctl --user daemon-real
    systemctl --user enable ncsync.service ncsync.timer
    systemctl --user start ncsync.service ncsync.timer
    else
    mkdir -p "$NCDEST"
    systemctl --user enable ncsync.service ncsync.timer
    systemctl --user start ncsync.service ncsync.timer
    fi
    zenity --info --text="Once your files are synced, re-run this script to add games or place the synced files in their correct location."
}
definition_seleciton() { # ask the user how we will define the save game locations
    echo "starting ${FUNCNAME[0]}"
    CHOICE=$(zenity --list --title="Save Game Locations Definition Selection" --column="Options" \ "How will the save game locations be defined?" \
    "Choose from Supported Games" "Select a Folder Manually")
    echo "CHOICE selected: $CHOICE"
    if [ "$CHOICE" = "Choose from Supported Games" ]; then
        choose_game
    elif [ "$CHOICE" = "Select a Folder Manually" ]; then
        define_folder
    fi
}
choose_game() { # choose from the list of supported games
    echo "starting ${FUNCNAME[0]}"
    zenity --info --text="If you want to help add games to this list for other users, find the location of the games' save files and provide it to the guy who wrote this."
    GAMES=$(cut -d'|' -f1 ./supportedgames.txt | sed 's/"//g')
    GAMENAME=$(echo "$GAMES" | zenity --list --title="Select a Game" --column="Games" --width=600 --height=600 )
    SAVEGAMEFOLDER=$(grep -i "^$GAMENAME|" ./supportedgames.txt | cut -d'|' -f2)
    SAVEGAMEFOLDER=$(eval echo "$SAVEGAMEFOLDER")
    echo "GAME: $GAMENAME FOLDER: $SAVEGAMEFOLDER"
    link_savefile
}
define_folder() { # let the user define the folder we're going to link.
    echo "starting  ${FUNCNAME[0]}"
    VALUES=$(zenity --forms --title="Nextcloud Configuration" --text="" --width=600 \
        --add-entry="Game Name:"
        --add-entry="Path to the directory containing the save game:" \
        --separator="|")
    GAMENAME=$(echo "$VALUES" | cut -d '|' -f1)
    SAVEGAMEFOLDER=$(echo "$VALUES" | cut -d '|' -f2)
    link_savefile
}
whattolink(){ # csgames.txt folder already exists, what are we doing here?
    echo "starting  ${FUNCNAME[0]}"
    CHOICE=$(zenity --list --title="Files should already be syncing." --column="Options" \ "What are we doing??" \
    "Placing cloudsave folders in their correct locations on another PC" "Adding a game to the list" "Update Service")
    echo "CHOICE selected: $CHOICE"

    if [ "$CHOICE" = "Placing cloudsave folders in their correct locations on another PC" ]; then
        LINK_EXISTING="TRUE"
        link_existing
    elif [ "$CHOICE" = "Adding a game to the list" ]; then
        definition_seleciton
    elif [ "$CHOICE" = "Update Service" ]; then
        UPDATE="TRUE"
        cloud_selector

    fi
}
link_existing(){ # we run the link_savefile function for every game in csgames.txt
    echo "starting  ${FUNCNAME[0]}"
    echo "link_existing"
    cat "$NCDEST/csgames.txt"
    while IFS='|' read -r GAMENAME SAVEGAMEFOLDER; do
        GAMENAME=$(echo "$GAMENAME" | sed 's/"//g')  # Remove quotes if present
        SAVEGAMEFOLDER=$(eval echo "$SAVEGAMEFOLDER")
        echo "GAME: $GAMENAME FOLDER: $SAVEGAMEFOLDER"
        link_savefile
    done < "$NCDEST/csgames.txt"
}
link_savefile(){ # link the SAVEGAMEFOLDER
    echo "starting  ${FUNCNAME[0]}"
    NCDEST=$(echo "$NCFOLDERS" | cut -d: -f1)
    NCSOURCE=$(echo "$NCFOLDERS" | cut -d: -f2)
    if [ "$LINK_EXISTING" = "TRUE" ]; then
        echo "making "$(eval echo "$SAVEGAMEFOLDER")""
        mkdir -p "$(dirname "$(eval echo "$SAVEGAMEFOLDER")")"
        echo "executing ln -s "$NCDEST/csgames/$GAMENAME/$(basename "$SAVEGAMEFOLDER")" "$(eval echo "$SAVEGAMEFOLDER")""
        ln -s "$NCDEST/csgames/$GAMENAME/$(basename "$SAVEGAMEFOLDER")" "$(eval echo "$SAVEGAMEFOLDER")"
    else
        echo "$GAMENAME|${SAVEGAMEFOLDER/$HOME/\$HOME}" >> $NCDEST/csgames.txt
        mkdir -p "$NCDEST/csgames/$GAMENAME"
        mv "$SAVEGAMEFOLDER" "$NCDEST/csgames/$GAMENAME"
        echo "executing ln -s "$NCDEST/csgames/$GAMENAME/$(basename "$SAVEGAMEFOLDER")" "$SAVEGAMEFOLDER""
        ln -s "$NCDEST/csgames/$GAMENAME/$(basename "$SAVEGAMEFOLDER")" "$SAVEGAMEFOLDER"
    fi
}
logcheck

