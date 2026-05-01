#!/usr/bin/env bash

rofi_theme="$(dirname "$0")/rounded-nord-dark.rasi"

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

# Get cliphist history
cliphist_output=$(cliphist list)

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
	local options="$cliphist_output"
	for cmd_entry in "${custom_commands[@]}"; do
		local display="${cmd_entry%,*}"
		options=$(printf "%s\n%s" "$options" "$display")
	done

	local MESG="""<span size=\"x-small\">Alt + Enter for more actions.</span>"""

	echo "$options" | rofi \
		-dmenu \
		-i \
		-display-columns 2 \
		-p "cliphist" \
		-mesg "$MESG" \
		-theme "$rofi_theme" \
		-me-select-entry '' \
		-me-accept-entry MousePrimary \
		-hover-select \
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
		-hover-select

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
				# First copy to clipboard
				echo "$selected" | cliphist decode | wl-copy
				# Then delete from history using delete-query
				echo "$selected" | awk '{print $2}' | xargs cliphist delete-query
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
