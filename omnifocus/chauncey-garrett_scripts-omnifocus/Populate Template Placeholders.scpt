(*
	Populate Template Placeholders

	This script populates a copy of a template by replacing placeholders with text.

	by Curt Clifton

	Copyright © 2007–2014, Curtis Clifton

	All rights reserved.

	Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

		• Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

		• Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

	Version History:

		0.8.1, updated instructions with new screen shot and additional details on dates
		0.8, updated for OmniFocus 2 and to use Notification Center
		0.7.2b, turns off autosave during execution of duplication and change to reduce number of transactions created. Fixed bug in handling of projects without placeholders. Thanks to Tommy Bollman for the fix. Removes Growl support.
		0.7.1, gracefully handles more unexpected user actions
		0.7, populates projects with dates but no other placeholders, cleans up after itself on Cancel
		0.6.2, detects if user is attempting to Populate something other than a Project
		0.6.1, optimized placeholder replacement: fixes bug with apostrophes in replacements and is also faster
		0.6, looks for paragraph beginning "Due Date is" in the note of the template project and uses that as a prompt in the due date dialog box.  Fixed bug where due times were munged if project start or due date wasn't set to 12am.
		0.5.1 updated for OmniFocus AppleScript dictionary change
		0.5, added Growl notifications, better error checking, bug fix in date handling, work around for OF multiple-window bug, and replacement of placeholders in notes
		0.4, automatically duplicates the project, works with content pane or sidebar selection
		0.3, now works for subprojects
		0.2, clears placeholders from note of project
		0.1, initial release, 6/13/07

*)

property placeholderOpener : "«"
property placeholderCloser : "»"

(*
	The following properties are used for script notifications.
*)
property scriptSuiteName : "Curt’s Scripts"

(*
	The following properties are used for debugging.  You probably don’t want to mess with them.  Just sayin’.
*)
property abortAfterInputChecks : false
property inDebugMode : false

tell application "OmniFocus"
	tell front document
		tell document window 1 -- (first document window whose index is 1)
			set theSelectedItems to selected trees of content
			if ((count of theSelectedItems) ≠ 1) then
				-- try sidebar selection
				set theSelectedItems to selected trees of sidebar
			end if
		end tell
		if ((count of theSelectedItems) < 1) then
			display alert "You must first select the project to populate." message "Select a single project that includes template placeholders." as warning
			return
		end if
		if ((count of theSelectedItems) > 1) then
			display alert "You must select just one project." message "Select a single project that includes template placeholders, but don‘t select the actions and subprojects under it." as warning
			return
		end if

		set selectedItem to value of item 1 of theSelectedItems
		set theProjectName to name of item 1 of theSelectedItems
		if (class of selectedItem is not project) then
			display alert "The selected item, “" & theProjectName & "” is not a project." message "The script only works with projects, not actions or folders.  Please select a project to use the script." as warning buttons {"OK"} default button 1
			return
		end if
		set theNote to note of selectedItem
		set thePlaceholders to {}
		try
			set thePlaceholderString to last paragraph of theNote
			set thePlaceholders to my parsePlaceholderString(thePlaceholderString)
		end try
		set theStartDate to defer date of selectedItem
		set theDueDate to due date of selectedItem
		if (theStartDate is missing value and theDueDate is missing value and (count of thePlaceholders) is 0) then
			display alert "This project, “" & theProjectName & "”, does not contain any information to populate." message "The note of a project should end with a list of project placeholders, like “" & placeholderOpener & "RoomName" & placeholderCloser & " " & placeholderOpener & "ClientName" & placeholderCloser & "”, or the project should have a start or due date that will be used to adjust the dates of items within the project." as warning buttons {"OK"} default button 1
			return
		end if

		set theReplacements to my getReplacements(thePlaceholders, {})
		if (theReplacements is missing value) then return -- cancelled

		if (theDueDate is not missing value) then
			set dueDatePrompt to my extractDueDatePrompt(theNote)
			set dateDifferential to my getDateDifferential("due", theDueDate, dueDatePrompt)
			if (dateDifferential is missing value) then return -- cancelled
		else if (theStartDate is not missing value) then
			set dateDifferential to my getDateDifferential("start", theStartDate, missing value)
			if (dateDifferential is missing value) then return -- cancelled
		else
			set dateDifferential to missing value
		end if

		-- When debugging, it's handy to abort the script before any changes are made to the OF database
		if abortAfterInputChecks then
			return
		end if

		duplicate (selectedItem) to after last section
		set duplicatedItem to last section

		try
			set theTask to {(get root task of duplicatedItem)}
		on error msg number num
			if num is -1700 then
				set theTask to {duplicatedItem}
			else
				beep
				error msg number num
			end if
		end try
		try
			set will autosave to false
			my replacePlaceholders(theTask, thePlaceholders, theReplacements, dateDifferential)
			set theNote to (stripPlaceholders of me from theNote)
			set theNote to (my replaceText(theNote, thePlaceholders, theReplacements))
			set note of duplicatedItem to theNote
			set next review date of duplicatedItem to (current date)
		on error msg number num
			-- make sure the autosave is turned back on
			set will autosave to true
			beep
			error msg number num
		end try
		set will autosave to true
	end tell
	my notify("Template Populated", "The project template has been populated.  You’ll find it at the end of the project listing.")

end tell

on parsePlaceholderString(theString)
	set oldDelim to AppleScript's text item delimiters
	set AppleScript's text item delimiters to placeholderOpener
	set firstParse to rest of text items of theString
	set AppleScript's text item delimiters to placeholderCloser
	set theResult to cleanPlaceholders(firstParse, {})
	set AppleScript's text item delimiters to oldDelim
	return theResult
end parsePlaceholderString

(* assumes that AppleScript's text item delimiters is set to placeholderCloser *)
on cleanPlaceholders(theList, accum)
	if (theList is {}) then return accum
	set firstItem to item 1 of theList
	set firstItem to text item 1 of firstItem
	if ((count of characters of firstItem) is not 0) then
		set end of accum to firstItem
	end if
	return cleanPlaceholders(rest of theList, accum)
end cleanPlaceholders

(* prompts user for a replacement string for each placeholder string *)
on getReplacements(thePlaceholders, accum)
	if (thePlaceholders is {}) then return accum
	set thePlaceholder to item 1 of thePlaceholders
	try
		tell application "OmniFocus"
			set reply to display dialog thePlaceholder & ":" default answer "" with title "Enter replacement for placeholder"
		end tell
	on error
		return missing value
	end try
	set end of accum to (text returned of reply)
	return getReplacements(rest of thePlaceholders, accum)
end getReplacements

on getDateDifferential(dateKind, originalDate, extraPrompt)
	if extraPrompt is missing value then
		set extraPrompt to ""
	else
		set extraPrompt to return & extraPrompt
	end if
	set validInput to false
	set theAnswer to ""
	repeat until validInput
		tell application "OmniFocus"
			set theReply to display dialog ("Enter " & dateKind & " date for project" & extraPrompt) default answer theAnswer with title "Enter Date"
		end tell
		try
			set theAnswer to text returned of theReply
		on error
			-- user cancelled
			return missing value
		end try
		try
			set newDate to date theAnswer
			set time of newDate to time of originalDate
			set validInput to true
		on error
			-- probably a conversion error
		end try
		if (not validInput) then beep
	end repeat
	return (newDate - originalDate)
end getDateDifferential

on replacePlaceholders(theTasks, thePlaceholders, theReplacements, dateDifferential)
	if (theTasks is {}) then return
	replacePlaceholdersInChildren(item 1 of theTasks, thePlaceholders, theReplacements, dateDifferential)
	replacePlaceholders(rest of theTasks, thePlaceholders, theReplacements, dateDifferential)
end replacePlaceholders

on replacePlaceholdersInChildren(theTask, thePlaceholders, theReplacements, dateDifferential)
	using terms from application "OmniFocus"
		set oldName to name of theTask as string
		if oldName contains placeholderOpener then
			set name of theTask to (my replaceText(oldName, thePlaceholders, theReplacements))
		end if
		set due date of theTask to (my updateDate(due date of theTask, dateDifferential))
		set defer date of theTask to (my updateDate(defer date of theTask, dateDifferential))
		set oldNote to note of theTask
		if (oldNote is not missing value and oldNote contains placeholderOpener) then
			set note of theTask to (my replaceText(oldNote, thePlaceholders, theReplacements))
		end if
		my replacePlaceholders(tasks of theTask, thePlaceholders, theReplacements, dateDifferential)
	end using terms from
end replacePlaceholdersInChildren

on replaceText(theText, thePlaceholders, theReplacements)
	if (thePlaceholders is {}) then
		return theText
	end if
	set oldTID to AppleScript's text item delimiters
	set wrappedPlaceholder to placeholderOpener & (item 1 of thePlaceholders) & placeholderCloser
	set AppleScript's text item delimiters to wrappedPlaceholder
	set itemList to every text item of theText
	set AppleScript's text item delimiters to item 1 of theReplacements
	set resultText to itemList as string
	set AppleScript's text item delimiters to oldTID
	return my replaceText(resultText, rest of thePlaceholders, rest of theReplacements)
end replaceText

on updateDate(originalDate, dateDifferential)
	if (originalDate is missing value or dateDifferential is missing value) then return missing value
	set newDate to originalDate + dateDifferential
	return newDate
end updateDate

on stripPlaceholders from theNote
	if ((count of paragraphs of theNote) ≤ 1) then return ""
	set noteParts to text from paragraph 1 to paragraph -2 of theNote
	return noteParts
end stripPlaceholders

on extractDueDatePrompt(theNote)
	set thePars to every paragraph of theNote
	repeat with aPar in thePars
		if aPar starts with "Due Date" then
			return aPar
		end if
	end repeat
	return missing value
end extractDueDatePrompt

(*
	Uses Notification Center to display a notification message.
	theTitle – a string giving the notification title
	theDescription – a string describing the notification event
*)
on notify(theTitle, theDescription)
	display notification theDescription with title scriptSuiteName subtitle theTitle
end notify

