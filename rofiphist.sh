#!/usr/bin/env bash

rofi_theme="$(dirname "$0")/rounded-nord-dark.rasi"
img_cache_dir="/tmp/cliphist"

show_help() {
	local script_name
	script_name=$(basename "$0")

	cat <<EOF
Usage:
  $script_name [--theme PATH]
  $script_name help

Options:
  --theme PATH      Use the rofi theme at PATH.
  --theme=PATH      Use the rofi theme at PATH.
  -h, --help, help  Show this help message.

Default theme:
  $rofi_theme
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	help | -h | --help)
		show_help
		exit 0
		;;
	--theme)
		if [ -z "$2" ]; then
			echo "Error: --theme requires a path" >&2
			exit 1
		fi
		rofi_theme="$2"
		shift 2
		;;
	--theme=*)
		rofi_theme="${1#*=}"
		shift
		;;
	*)
		echo "Error: unknown option: $1" >&2
		echo "Run '$0 help' for usage." >&2
		exit 1
		;;
	esac
done

# Initialize image cache directory (clear stale thumbnails on each run)
rm -rf "$img_cache_dir"
mkdir -p "$img_cache_dir"

# Preprocess cliphist list output:
#   - Previewable images (jpg/jpeg/png/bmp/gif/webp): decode to thumbnail, append \0icon\x1f<path>
#   - Other binary entries: reformat as "<id>\t[file: <mime>]"
#   - Text entries: pass through unchanged
prepare_cliphist_list() {
	gawk -v cache="$img_cache_dir" '
		# Skip stray HTML meta lines that cliphist may emit
		/^[0-9]+[ \t]<meta http-equiv=/ { next }

		# Previewable image formats: generate thumbnail and attach icon path
		match($0, /^([0-9]+)[ \t].*binary.*(jpg|jpeg|png|bmp|gif|webp)/, grp) {
			id  = grp[1]
			ext = grp[2]
			out = cache "/" id "." ext
			# Write the full entry line to a temp file, then decode via stdin redirect.
			# cliphist decode requires the complete "id\t..." line; plain "echo id" fails
			# because the trailing newline breaks strconv.Atoi in cliphist ID parsing.
			tmpfile = cache "/_in_" id
			print $0 > tmpfile
			close(tmpfile)
			system("cliphist decode < " tmpfile " > " out " 2>/dev/null; rm -f " tmpfile)
			print $0 "\0icon\x1f" out
			next
		}

		# Other binary entries: show "[file: mime/type]" instead of raw binary metadata
		/binary/ {
			match($0, /^([0-9]+)[ \t]/, id_grp)
			id = id_grp[1]
			if (match($0, /\] ([a-zA-Z0-9_.+-]+\/[a-zA-Z0-9_.+-]+) \]/, mime_grp)) {
				print id "\t[file: " mime_grp[1] "]"
			} else {
				print id "\t[binary data]"
			}
			next
		}

		# Regular text entries
		{ print }
	'
}

# Write processed cliphist list to a temp file.
# Must use a file (not a variable) because bash $() strips null bytes,
# and rofi's icon syntax requires a literal null byte: \0icon\x1f<path>
cliphist_list_file="$img_cache_dir/list"
cliphist list | prepare_cliphist_list > "$cliphist_list_file"

# Define custom commands as indexed array
# Format: "display_text,command"
custom_commands=(
	"	> Wipe,cliphist wipe"
	"	> Compact,cliphist compact"
)

# Define submenu actions as indexed array
# Format: "display_text,action_type"
submenu_actions=(
	"	> Copy,copy"
	"	> Copy and Delete,copy_and_delete"
	"	> Delete,delete"
)

# Function to check if item is custom command
is_custom_command() {
	local item="$1"
	for cmd_entry in "${custom_commands[@]}"; do
		local display="${cmd_entry%,*}"
		if [ "$display" = "$item" ]; then
			return 0
		fi
	done
	return 1
}

# Function to get value from array entry (display_text,value format)
entry_value() {
	local item="$1"
	local array_name="$2"

	# Use nameref to reference the array
	local -n array_ref="$array_name"

	for entry in "${array_ref[@]}"; do
		local display="${entry%,*}"
		local value="${entry#*,}"
		if [ "$display" = "$item" ]; then
			echo "$value"
			return
		fi
	done
}

# Function to check if item is submenu action and extract action type
is_submenu_action() {
	local item="$1"
	for action_entry in "${submenu_actions[@]}"; do
		local display="${action_entry%,*}"
		if [ "$display" = "$item" ]; then
			return 0
		fi
	done
	return 1
}

# Function to show main menu
show_main_menu() {
	local MESG="""<span size=\"x-small\">Alt + Enter for more actions.</span>"""

	# Stream list file (preserving null bytes for icon metadata) then append custom commands
	{
		cat "$cliphist_list_file"
		for cmd_entry in "${custom_commands[@]}"; do
			printf "%s\n" "${cmd_entry%,*}"
		done
	} | rofi \
		-dmenu \
		-i \
		-display-columns 2 \
		-p "cliphist" \
		-mesg "$MESG" \
		-theme "$rofi_theme" \
		-me-select-entry '' \
		-me-accept-entry MousePrimary \
		-hover-select \
		-show-icons \
		-kb-custom-1 "Alt+Return"

	return $?
}

# Function to show submenu for history items
show_submenu() {
	local selected="$1"
	local options="$selected"

	# Add submenu actions to submenu (in defined order)
	for action_entry in "${submenu_actions[@]}"; do
		local display="${action_entry%,*}"
		options=$(printf "%s\n%s" "$options" "$display")
	done

	# Add custom commands to submenu
	for cmd_entry in "${custom_commands[@]}"; do
		local display="${cmd_entry%,*}"
		options=$(printf "%s\n%s" "$options" "$display")
	done

	echo "$options" | rofi \
		-dmenu \
		-i \
		-display-columns 2 \
		-p "cliphist" \
		-theme "$rofi_theme" \
		-me-select-entry '' \
		-me-accept-entry MousePrimary \
		-hover-select \
		-show-icons

	return $?
}

# Main menu loop
while true; do
	selected=$(show_main_menu)
	exit_code=$?

	# If user cancels (press Esc or close window)
	if [ $exit_code -eq 1 ] || [ -z "$selected" ]; then
		exit 0
	fi

	# Check if selected item is a custom command
	if is_custom_command "$selected"; then
		eval "$(entry_value "$selected" custom_commands)"
		exit 0
	fi

	# If Alt+Return was pressed (exit code 10), show submenu
	if [ $exit_code -eq 10 ]; then
		submenu_choice=$(show_submenu "$selected")
		submenu_exit=$?

		# If user cancels submenu
		if [ $submenu_exit -eq 1 ] || [ -z "$submenu_choice" ]; then
			continue
		fi

		# Check if submenu choice is a custom command
		if is_custom_command "$submenu_choice"; then
			eval "$(entry_value "$submenu_choice" custom_commands)"
			exit 0
		fi

		# Execute submenu action based on choice
		if [ "$submenu_choice" = "$selected" ]; then
			# Copy selected item to clipboard
			echo "$selected" | cliphist decode | wl-copy
		elif is_submenu_action "$submenu_choice"; then
			action=$(entry_value "$submenu_choice" submenu_actions)

			case "$action" in
			copy)
				echo "$selected" | cliphist decode | wl-copy
				;;
			copy_and_delete)
				# First copy to clipboard, and the copied line will become the first item in cliphist.
				echo "$selected" | cliphist decode | wl-copy
				# Then delete the first item, which is the copied line.
				cliphist list | head -n 1 | cliphist delete
				;;
			delete)
				echo "$selected" | cliphist delete
				;;
			esac
		fi

		exit 0
	else
		# Normal Enter key (exit code 0) - copy history item to clipboard
		echo "$selected" | cliphist decode | wl-copy
		exit 0
	fi
done
