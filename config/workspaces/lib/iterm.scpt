-- iTerm2 AppleScript helpers for workspace management
-- Usage:
--   osascript iterm.scpt restore <arrangement-name>
--   osascript iterm.scpt save <arrangement-name>
--   osascript iterm.scpt close <arrangement-name>

on run argv
	if (count of argv) < 2 then
		log "Usage: osascript iterm.scpt <command> <arrangement-name>"
		return
	end if

	set cmd to item 1 of argv
	set arrangementName to item 2 of argv

	if cmd is "restore" then
		restoreArrangement(arrangementName)
	else if cmd is "save" then
		saveArrangement(arrangementName)
	else if cmd is "close" then
		closeArrangement(arrangementName)
	else
		log "Unknown command: " & cmd
	end if
end run

on restoreArrangement(arrangementName)
	tell application "iTerm2"
		activate
		try
			-- Check if arrangement exists before restoring
			set arrangementNames to name of every window arrangement
			if arrangementName is in arrangementNames then
				restore window arrangement arrangementName
			else
				-- Arrangement not saved yet — just open a new window
				create window with default profile
			end if
		on error errMsg
			log "Error restoring arrangement: " & errMsg
			-- Fallback: just activate iTerm2
			activate
		end try
	end tell
end restoreArrangement

on saveArrangement(arrangementName)
	tell application "iTerm2"
		try
			save window arrangement arrangementName
		on error errMsg
			log "Error saving arrangement: " & errMsg
		end try
	end tell
end saveArrangement

on closeArrangement(arrangementName)
	tell application "iTerm2"
		try
			-- Close all windows that belong to this arrangement
			-- iTerm2 doesn't track which windows came from which arrangement,
			-- so we close windows whose tabs match the arrangement's profile pattern
			set windowCount to count of windows
			repeat with i from windowCount to 1 by -1
				set w to window i
				try
					set tabCount to count of tabs of w
					set firstTab to tab 1 of w
					set sessionName to name of current session of firstTab
					if sessionName contains arrangementName then
						close w
					end if
				end try
			end repeat
		on error errMsg
			log "Error closing arrangement: " & errMsg
		end try
	end tell
end closeArrangement
