﻿; ahk: x86
; ahk: console
class GroupInfo {

	requires() {
		return [Ansi, Ldap, OptParser, String, System]
	}

	static RC_OK := -1
	static RC_MISSING_ARG := -2
	static RC_INVALID_ARGS := -3
	static RC_CYCLE_DETECTED := -4
	static RC_CN_NOT_FOUND := -5
	static RC_CN_AMBIGOUS := -6
	static RC_TOO_MANY_ARGS := -7

	static options := GroupInfo.setDefaults()

	static cn := ""
	static capturedRegExGroups := []
	static objectClassForGroupFilter := "groupOfNames"

	static ldapConnection := 0

	setDefaults() {
		return { append: ""
				, baseDn: ""
				, color: false
				, count: false
				, countOnly: false
				, useEnvironmentVariables: false
				, filter: "*"
				, group: ""
				, help: false
				, host: "localhost"
				, ibmAllGroups: false
				, ibmNestedGroups: false
				, ignoreCase: -1
				, lower: false
				, maxNestedLevel: 32
				, output: ""
				, port: 389
				, quiet: false
				, refs: false
				, regex: false
				, resultOnly: false
				, short: false
				, sort: false
				, tempFile: 0
				, upper: false
				, version: false }
	}

	cli() {
		op := new OptParser("gi [-a <filename> | -o <filename>] [options] "
				. "<cn> [filter]",, "GI_OPTIONS")
		op.add(new OptParser.String("a", "append", GroupInfo.options
				, "append", "file-name" ,"Append result to existing file"))
		op.add(new OptParser.String("o", "", GroupInfo.options, "output"
				, "file-name", "Write result to file"))
		op.add(new OptParser.Group("`nOptions"))
		op.add(new OptParser.Boolean("1", "short", GroupInfo.options
				, "short", "Display group names instead of the DN"))
		op.add(new OptParser.Boolean("c", "count", GroupInfo.options
				, "count", "Display number of hits"))
		op.add(new OptParser.Boolean("C", "count-only", GroupInfo.options
				, "countOnly"
				, "Return the number of hits as exit code; no other output"))
		op.add(new OptParser.Boolean("e", "regex", GroupInfo.options
				, "regex", "Use a regular expression to filter the result set "
				. "(see also "
				.  "http://ahkscript.org/docs/misc/RegEx-QuickRef.htm)"))
		op.add(new OptParser.String("h", "host", GroupInfo.options, "host"
				, "host-name", "Hostname of the LDAP server (default="
				. GroupInfo.options.host ")"
				,, GroupInfo.options.host, GroupInfo.options.host))
		op.add(new OptParser.String("p", "port", GroupInfo.options
				, "port", "portnum", "Port number of the LDAP server (default="
				. GroupInfo.options.port ")"
				,, GroupInfo.options.port, GroupInfo.options.port))
		op.add(new OptParser.String("b", "base-dn", GroupInfo.options
				, "baseDn", "basedn", "Base DN to start the search"
				,, GroupInfo.options.baseDn, GroupInfo.options.baseDn))
		op.add(new OptParser.Callback("g", "group", GroupInfo.options
				, "group", "captureRegExGroupCallback", "number"
				, "Return the group of regex evaluation as result (implies -e)"
				, OptParser.OPT_ARG))
		op.add(new OptParser.Boolean("i", "ignore-case", GroupInfo.options
				, "ignoreCase", "Ignore case when filtering results"
				, OptParser.OPT_NEG,, GroupInfo.options.ignoreCase
				, GroupInfo.options.ignoreCase))
		op.add(new OptParser.Boolean("l", "lower", GroupInfo.options
				, "lower", "Display result in lower case characters"))
		op.add(new OptParser.Boolean("u", "upper", GroupInfo.options
				, "upper", "Display result in upper case characters"))
		op.add(new OptParser.Boolean("r", "refs", GroupInfo.options
				, "refs", "Display group relations"))
		op.add(new OptParser.Boolean("s", "sort", GroupInfo.options
				, "sort", "Sort result"))
		op.add(new OptParser.Boolean(0, "color", GroupInfo.options, "color"
				, "Colored output "
				. "(deactivated by default if -a or -o option is set)"
				, OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE, -1, true))
		op.add(new OptParser.Boolean("R", "result-only", GroupInfo.options
				, "resultOnly"
				, "Suppress any other output than the found groups"))
		op.add(new OptParser.Boolean(0, "ibm-nested-group", GroupInfo.options
				, "ibmNestedGroups"
				, "Only show groups which implement "
				. "objectclass ibm-nestedGroup"))
		op.add(new OptParser.Boolean(0, "ibm-all-groups", GroupInfo.options
				, "ibmAllGroups", "Use 'ibm_allgroups' to retrieve data"))
		op.add(new OptParser.String(0, "max-nested-level", GroupInfo.options
				, "maxNestedLevel", "n"
				, "Defines, which recursion depth terminates the process "
				. "(default=32)"
				,, GroupInfo.options.maxNestedLevel
				, GroupInfo.options.maxNestedLevel))
		op.add(new OptParser.Boolean(0, "env"
				, GroupInfo.options, "useEnvironmentVariables"
				, "Ignore environment variable GI_OPTIONS"
				, OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
		op.add(new OptParser.Boolean("q", "quiet", GroupInfo.options, "quiet"
				, "Suppress output of results"))
		op.add(new OptParser.Boolean(0, "version", GroupInfo.options, "version"
				, "Print version info"))
		op.add(new OptParser.Boolean(0, "help", GroupInfo.options, "help"
				, "Print help", OptParser.OPT_HIDDEN))
		return op
	}

	run(commandLineArguments) {
		try {
			returnCode := GroupInfo.RC_OK
			optionParser := GroupInfo.cli()
			parsedArguments := optionParser.parse(commandLineArguments)
			if (GroupInfo.shallHelpOrVersionInfoBeDisplayed()) {
				returnCode := GroupInfo.showHelpOrVersionInfo(optionParser)
			} else {
				GroupInfo.evaluateCommandLineOptions(parsedArguments)
				GroupInfo.handleRegExCaptureGroups()
				GroupInfo.handleIBMnestedGroups()
				GroupInfo.handleRegExFilter()
				GroupInfo.handleParsedArguments(parsedArguments)
				GroupInfo.handleCountOnly()
				returnCode := GroupInfo.main()
			}
		}
		catch gotException {
			OutputDebug % gotException.what
					. "`nin: " gotException.file " #" gotException.line
			Ansi.writeLine(gotException.message)
			Ansi.writeLine(optionParser.usage())
		}
		finally {
			GroupInfo.doCleanup()
		}
		return returnCode
	}

	shallHelpOrVersionInfoBeDisplayed() {
		return GroupInfo.options.help || GroupInfo.options.version
	}

	showHelpOrVersionInfo(optionParser) {
		if (GroupInfo.options.help) {
			Ansi.writeLine(optionParser.usage())
		} else if (GroupInfo.options.version) {
			Ansi.writeLine(G_VERSION_INFO.NAME "/"
					. G_VERSION_INFO.ARCH "-b" G_VERSION_INFO.BUILD)
		}
		return ""
	}

	evaluateCommandLineOptions(parsedArguments) {
		if (parsedArguments.count() < 1) {
			throw Exception("error: Missing argument"
					,, GroupInfo.RC_MISSING_ARG)
		}
		if (parsedArguments.count() > 2) {
			throw Exception("error: Too many arguments"
					,, GroupInfo.RC_TOO_MANY_ARGS)
		}
		if (GroupInfo.options.output && GroupInfo.options.append) {
			throw Exception("error: Options '-o' and '-a' "
					. "cannot be used together"
					,, GroupInfo.RC_INVALID_ARGS)
		}
		if (GroupInfo.options.upper && GroupInfo.options.lower) {
			throw Exception("error: Options '-l' and '-u' "
					. " cannot be used together"
					,, GroupInfo.RC_INVALID_ARGS)
		}
		if (GroupInfo.options.ibmAllGroups && GroupInfo.options.refs) {
			throw Exception("error: Options '-r' and '--ibm-all-groups' "
					. "cannot be used together"
					,, GroupInfo.RC_INVALID_ARGS)
		}
		if (GroupInfo.options.ibmAllGroups
				&& GroupInfo.options.ibmNestedGroups) {
			throw Exception("error: Options '--ibm-nested-group' and "
					. " '--ibm-all-groups' cannot be used together"
					,, GroupInfo.RC_INVALID_ARGS)
		}
	}

	handleRegExCaptureGroups() {
		if (GroupInfo.capturedRegExGroups.maxIndex() != "") {
			GroupInfo.options.group := true
			if (!GroupInfo.options.regex) {
				GroupInfo.options.regex := true
			}
		}
	}

	handleIBMnestedGroups() {
		if (GroupInfo.options.ibmNestedGroups) {
			GroupInfo.objectClassForGroupFilter := "ibm-nestedGroup"
		}
	}

	handleParsedArguments(parsedArguments) {
		GroupInfo.cn := parsedArguments[1]
		if (parsedArguments.count() == 2) {
			GroupInfo.options.filter := parsedArguments[2]
		}
	}

	handleRegExFilter() {
		if (GroupInfo.options.regex) {
			GroupInfo.options.filter := "(.*)"
		}
	}

	handleCountOnly() {
		if (!GroupInfo.options.countOnly
				&& !GroupInfo.options.resultOnly) {
			Ansi.write("`nConnecting to " GroupInfo.options.host
					. ":" GroupInfo.options.port " ... ")
		}
	}

	doCleanup() {
		if (GroupInfo.ldapConnection) {
			GroupInfo.ldapConnection.unbind()
		}
		if (GroupInfo.options.tempFile) {
			GroupInfo.options.tempFile.close()
		}
	}

	main() {
		if (GroupInfo.options.sort
				|| GroupInfo.options.output
				|| GroupInfo.options.append) {
			GroupInfo.options.tempFile := FileOpen(A_Temp "\__gi__.dat", "w`n")
			if ((GroupInfo.options.output || GroupInfo.options.append)
					&& GroupInfo.options.color != true) {
				GroupInfo.options.color := false
			}
		}
		if (GroupInfo.options.ibmNestedGroups) {
			GroupInfo.objectClassForGroupFilter := "ibm-nestedGroup"
		}
		GroupInfo.ldapConnection := new Ldap(GroupInfo.options.host
				, GroupInfo.options.port)
		GroupInfo.ldapConnection.setOption(Ldap.OPT_VERSION, Ldap.VERSION3)
		GroupInfo.ldapConnection.connect()
		if ( !GroupInfo.options.countOnly && !GroupInfo.options.resultOnly) {
			Ansi.writeLine("Ok.")
		}
		dn := GroupInfo.findDnByFilter("(cn=" GroupInfo.cn ")")
		if (!GroupInfo.options.countOnly && !GroupInfo.options.resultOnly) {
			Ansi.writeLine(GroupInfo.formatOutput(dn, ""), true)
		}
		if (!GroupInfo.options.ibmAllGroups) {
			numberOfHits := GroupInfo.groupsInWhichDnIsMember(dn
					, new GroupInfo.GroupData())
		} else {
			numberOfHits
					:= GroupInfo.groupsOfCnByUsingIbmAllGroups(GroupInfo.cn)
		}

		; Handle sort and/or output options; ---------------------------------
		if (GroupInfo.options.tempFile) {
			GroupInfo.options.tempFile.close()
		}
		content := ""
		if (GroupInfo.options.tempFile) {
			h_gi := FileOpen(A_Temp "\__gi__.dat", "r`n")
			content := h_gi.read(h_gi.length)
			h_gi.close()
			; FileRead content, %A_Temp%\__gi__.dat
			if (GroupInfo.options.sort) {
				Sort content
			}
			FileDelete %A_Temp%\__gi__.dat
		}
		if (GroupInfo.options.append) {
			file_name := GroupInfo.options.append
		} else if (GroupInfo.options.output) {
			file_name := GroupInfo.options.output
			if (FileExist(file_name)) {
				FileDelete %file_name%
			}
		} else {
			file_name := "*"
		}
		if (file_name = "*") {
			Ansi.write(content)
		} else {
			FileAppend %content%, %file_name%
		}
		content := ""
		if (GroupInfo.options.count) {
			Ansi.writeLine("`n" numberOfHits " Hit(s)")
		}
		return numberOfHits
	}

	formatOutput(text, ref) {
		if (GroupInfo.options.refs) {
			if (GroupInfo.options.short) {
				if (RegExMatch(ref, "^.*?=(.*?),.*$", $)) {
					ref := $1
				}
			}
		} else {
			ref := ""
		}
		if (GroupInfo.options.short) {
			if (RegExMatch(text, "^.*?=(.*?),.*$", $)) {
				text := $1
			}
		}
		if (GroupInfo.options.upper) {
			text := text.upper()
			ref := ref.upper()
		} else if (GroupInfo.options.lower) {
			text := text.lower()
			ref := ref.lower()
		}
		if (GroupInfo.options.color) {
			text := RegExReplace(text, "(?P<attr>\w+=)"
					, Ansi.setGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD)
					. "${attr}"
					. Ansi.setGraphic(Ansi.ATTR_OFF))
			if (GroupInfo.options.refs && ref != "") {
				ref := Ansi.setGraphic(Ansi.FOREGROUND_RED, Ansi.ATTR_BOLD)
						. "  <-(" RegExReplace(ref, "(?P<attr>\w+=)"
						, Ansi.setGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD)
						. "${attr}"
						. Ansi.setGraphic(Ansi.ATTR_OFF))
						. Ansi.setGraphic(Ansi.FOREGROUND_RED, Ansi.ATTR_BOLD)
						. ")" Ansi.setGraphic(Ansi.ATTR_OFF)
			}
		}
		else {
			if (GroupInfo.options.refs) {
				ref := "  <-(" ref ")"
			}
		}
		return text ref
	}

	processOutput(text) {
		isOutputPrinted := true
		try {
			if (!GroupInfo.options.quiet
					&& isOutputPrinted := Ansi.plainStr(text)
					.filter(GroupInfo.options.filter, GroupInfo.options.regex
					, (GroupInfo.options.ignoreCase == true ? true : false)
					, false
					, match := "")) {
				if (GroupInfo.capturedRegExGroups.maxIndex() != "") {
					text := ""
					loop % match.count {
						text .= match[GroupInfo.capturedRegExGroups[A_Index]]
					}
				}
				if (GroupInfo.options.tempFile) {
					GroupInfo.options.tempFile.writeLine(((
							!GroupInfo.options.output
							&& !GroupInfo.options.append
							&& !GroupInfo.options.resultOnly)
							? "   " : "") text)
				}
				else if (!GroupInfo.options.countOnly) {
					Ansi.writeLine((!GroupInfo.options.resultOnly
							? "   "
							: "") text, true)
				}
			}
		}
		catch gotException {
			isOutputPrinted := false
			throw gotException
		}
		return isOutputPrinted
	}

	groupsInWhichDnIsMember(memberDn, groupData) {
		if (!GroupInfo.ldapConnection.search(searchResult
				, GroupInfo.options.baseDn
				, "(&(objectclass=" GroupInfo.objectClassForGroupFilter ")"
				. "(member=" memberDn "))") == Ldap.LDAP_SUCCESS) {
			throw Exception(Ldap.err2String(GroupInfo.ldapConnection
					.getLastError()))
		}
		numberOfEntriesFound
				:= GroupInfo.ldapConnection.countEntries(searchResult)
		if (numberOfEntriesFound < 0) {
			throw "error: " Exception(Ldap.err2String(GroupInfo
					.ldapConnection.getLastError()))
		}
		loop %numberOfEntriesFound% {
			if (A_Index = 1) {
				member := GroupInfo.ldapConnection.firstEntry(searchResult)
			} else {
				member := GroupInfo.ldapConnection.nextEntry(member)
			}
			if (member) {
				if (!(dn := GroupInfo.ldapConnection.getDn(member))) {
					throw Exception(Ldap.err2String(GroupInfo.ldapConnection
							.getLastError()))
				}
				if (groupData.groupsOfDn[dn] == "" || GroupInfo.options.refs) {
					if (GroupInfo.processOutput(GroupInfo.formatOutput(dn
							, memberDn))) {
						groupData.numberOfGroups++
					}
					groupData.groupsOfDn[dn] := 1
				}
				groupData.nestedLevel++
				if (groupData.nestedLevel > GroupInfo.options.maxNestedLevel) {
					throw Exception("error: Cyclic reference detected: `n`t"
							. dn "`n`t<- " memberDn,, RC_CYCLE_DETECTED)
				}
				GroupInfo.groupsInWhichDnIsMember(dn, groupData)
				groupData.nestedLevel--
			}
		}
		return groupData.numberOfGroups
	}

	findDnByFilter(ldapFilter) {
		if (GroupInfo.ldapConnection.search(searchResult
				, GroupInfo.options.baseDn
				, ldapFilter) != Ldap.LDAP_SUCCESS) {
			throw Exception(Ldap.err2String(GroupInfo.ldapConnection
					.getLastError()))
		}
		numberOfEntriesFound
				:= GroupInfo.ldapConnection.countEntries(searchResult)
		if (numberOfEntriesFound < 0) {
			throw "error: " Exception(Ldap.err2String(GroupInfo
					.ldapConnection.getLastError()))
		}
		if (numberOfEntriesFound = 0) {
			throw Exception("error: cn not found """ ldapFilter """"
					,, RC_CN_NOT_FOUND)
		} else if (numberOfEntriesFound > 1) {
			throw Exception("error: cn is ambigous (" numberOfEntriesFound ") "
					. """" ldapFilter """",, RC_CN_AMBIGOUS)
		}
		entry := GroupInfo.ldapConnection.firstEntry(searchResult)
		return GroupInfo.ldapConnection.getDn(entry)
	}

	groupsOfCnByUsingIbmAllGroups(cn) {
		numberOfGroups := 0
		groupsOfCn := []
		if (!GroupInfo.ldapConnection.search(searchResult
				, GroupInfo.options.baseDn, "(cn=" cn ")"
				,, ["ibm-allgroups"]) == Ldap.LDAP_SUCCESS) {
			throw Exception("error" Ldap.err2String(GroupInfo.ldapConnection
					.getLastError()))
		}
		numberOfEntriesFound
				:= GroupInfo.ldapConnection.countEntries(searchResult)
		if (numberOfEntriesFound < 0) {
			throw "error: " Ldap.err2String(GroupInfo.ldapConnection
					.getLastError())
		}
		loop %numberOfEntriesFound% {
			if (A_Index == 1) {
				memberEntry := GroupInfo.ldapConnection.firstEntry(searchResult)
			} else {
				memberEntry := GroupInfo.ldapConnection.nextEntry(memberEntry)
			}
			ibmAllGroupsAttribute
					:= GroupInfo.ldapConnection.firstAttribute(memberEntry)
			attributeValues := GroupInfo.ldapConnection.getValues(memberEntry
					, ibmAllGroupsAttribute)
			groupsOfCn := System.ptrListToStrArray(attributeValues)
			numberOfGroups := groupsOfCn.maxIndex()
			loop %numberOfGroups% {
				GroupInfo.processOutput(GroupInfo
						.formatOutput(groupsOfCn[A_Index], ""))
			}
		}
		return numberOfGroups
	}

	class GroupData {
		numberOfGroups := 0
		nestedLevel := 0
		groupsOfDn := []
	}
}

captureRegExGroupCallback(number, no_opt="") {
	GroupInfo.capturedRegExGroups.push(number)
}

#NoEnv ; notest-begin
#Warn All, StdOut
ListLines Off
SetBatchLines, -1

#Include <App>
#Include <cui-libs>
#Include <Ldap>
#Include <System>
#Include *i %A_ScriptDir%\gi.versioninfo

#Include <modules\structure\LDAPAPIInfo>
#Include <modules\structure\LDAPMod>

Main:
exitapp App.checkRequiredClasses(GroupInfo).run(A_Args) ; notest-end
; vim:tw=0:ts=4:sts=4:sw=4:noet:ft=autohotkey:bomb
