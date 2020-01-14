﻿; ahk: x86
; ahk: console
class GroupInfo extends LdapTool {

	requires() {
		return [Ansi, Ldap, Object, OptParser, String, System]
	}

	#Include %A_LineFile%\..\modules
	#Include entry.ahk

	static options := GroupInfo.setDefaults()

	static cn := ""
	static capturedRegExGroups := []

	setDefaults() {
		return Object.append(base.options.clone()
				, {ibmAllGroups: false})
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
				returnCode := GroupInfo.handleHitCount(GroupInfo.main())
			}
		} catch gotException {
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
		op.add(new OptParser.Line("--[no]env"
				, "Ignore environment variable GI_OPTIONS"))
		op.add(new OptParser.Boolean("q", "quiet", GroupInfo.options, "quiet"
				, "Suppress output of results"))
		op.add(new OptParser.Boolean(0, "version", GroupInfo.options, "version"
				, "Print version info"))
		op.add(new OptParser.Boolean(0, "help", GroupInfo.options, "help"
				, "Print help", OptParser.OPT_HIDDEN))
		return op
	}

	evaluateCommandLineOptions(parsedArguments) {
		base.evaluateCommandLineOptions(parsedArguments)
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
			GroupInfo.options.filterObjectClass := "ibm-nestedGroup"
		}
	}

	handleRegExFilter() {
		if (GroupInfo.options.regex) {
			GroupInfo.options.filter := "(.*)"
		}
	}

	handleHitCount(numberOfHits) {
		if (GroupInfo.options.count) {
			Ansi.writeLine("`n" numberOfHits " Hit(s)")
		}
		return numberOfHits
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
		GroupInfo.openTempFileIfNecessary()
		GroupInfo.connectToLdapServer()
		dn := GroupInfo.findDnByFilter("(cn=" GroupInfo.cn ")")
		numberOfHits := (GroupInfo.options.ibmAllGroups
				? GroupInfo.groupsOfCnByUsingIbmAllGroups(GroupInfo.cn)
				: GroupInfo.groupsInWhichDnIsMember(dn
				, new GroupInfo.GroupData))
		if (GroupInfo.tempFileWasNecessary()) {
			GroupInfo.distributeTempFileContent()
		}
		return numberOfHits
	}

	connectToLdapServer() {
		GroupInfo.ldapConnection := new Ldap(GroupInfo.options.host
				, GroupInfo.options.port)
		GroupInfo.ldapConnection.setOption(Ldap.OPT_VERSION, Ldap.VERSION3)
		GroupInfo.ldapConnection.connect()
		if (!GroupInfo.options.countOnly && !GroupInfo.options.resultOnly) {
			Ansi.writeLine("Ok.")
		}
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
		dn := GroupInfo.ldapConnection.getDn(entry)
		if (!GroupInfo.options.countOnly && !GroupInfo.options.resultOnly) {
			Ansi.writeLine(new GroupInfo.Entry(dn, "", GroupInfo.options).dn)
		}
		return dn
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
		numberOfEntriesFound := GroupInfo.checkNumberOfEntries(searchResult)
		loop %numberOfEntriesFound% {
			memberEntry := (A_Index == 1
					? GroupInfo.ldapConnection.firstEntry(searchResult)
					: GroupInfo.ldapConnection.nextEntry(memberEntry))
			ibmAllGroupsAttribute
					:= GroupInfo.ldapConnection.firstAttribute(memberEntry)
			attributeValues := GroupInfo.ldapConnection.getValues(memberEntry
					, ibmAllGroupsAttribute)
			groupsOfCn := System.ptrListToStrArray(attributeValues)
			numberOfGroups := 0
			loop % groupsOfCn.count() {
				if (GroupInfo.processOutput(new GroupInfo
						.Entry(groupsOfCn[A_Index], "", GroupInfo.options))) {
					numberOfGroups++
				}
			}
		}
		return numberOfGroups
	}

	groupsInWhichDnIsMember(memberDn, groupData) {
		numberOfEntriesFound := GroupInfo
				.searchGroupsInWhichDnIsMember(memberDn, groupData)
		loop %numberOfEntriesFound% {
			member := (A_Index == 1
					? GroupInfo.ldapConnection.firstEntry(groupData.searchResult) ; ahklint-ignore: W002
					: GroupInfo.ldapConnection.nextEntry(member))
			if (member) {
				if (!(dn := GroupInfo.ldapConnection.getDn(member))) {
					throw Exception(Ldap.err2String(GroupInfo.ldapConnection
							.getLastError()))
				}
				if (groupData.groupsOfDn[dn] == "" || GroupInfo.options.refs) {
					if (GroupInfo.processOutput(new GroupInfo.Entry(dn
							, memberDn, GroupInfo.options))) {
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

	searchGroupsInWhichDnIsMember(memberDn, groupData) {
		if (!GroupInfo.ldapConnection.search(searchResult
				, GroupInfo.options.baseDn
				, "(&(objectclass=" GroupInfo.options.filterObjectClass ")"
				. "(member=" memberDn "))") == Ldap.LDAP_SUCCESS) {
			throw Exception(Ldap.err2String(GroupInfo.ldapConnection
					.getLastError()))
		}
		groupData.searchResult := searchResult
		return GroupInfo.checkNumberOfEntries(searchResult)
	}

	checkNumberOfEntries(searchResult) {
		numberOfEntriesFound
				:= GroupInfo.ldapConnection.countEntries(searchResult)
		if (numberOfEntriesFound < 0) {
			throw "error: " Exception(Ldap.err2String(GroupInfo
					.ldapConnection.getLastError()))
		}
		return numberOfEntriesFound
	}

	processOutput(entry) {
		if (!GroupInfo.options.quiet) {
			try {
				isDnMatchingTheFilter := GroupInfo.filterOutput(entry)
			} catch gotException {
				throw gotException
			}
		}
		return isDnMatchingTheFilter
	}

	filterOutput(entry) {
		if (isDnMatchingTheFilter
				:= entry.handleCase(entry.handleShort(entry.theDn))
				.filter(GroupInfo.options.filter, GroupInfo.options.regex
				, (GroupInfo.options.ignoreCase == true ? true : false)
				, false
				, matches := "")) {
			entry.theDn := GroupInfo.rewriteDnWithMatches(entry.theDn, matches)
			GroupInfo.writeOutput(entry.toString())
		}
		return isDnMatchingTheFilter
	}

	rewriteDnWithMatches(dn, matches) {
		if (GroupInfo.capturedRegExGroups.maxIndex() != "") {
			dn := ""
			loop % matches.count {
				dn .= matches[GroupInfo.capturedRegExGroups[A_Index]]
			}
		}
		return dn
	}

	writeOutput(text) {
		if (GroupInfo.options.tempFile) {
			GroupInfo.options.tempFile.writeLine(((
					!GroupInfo.options.output
					&& !GroupInfo.options.append
					&& !GroupInfo.options.resultOnly)
					? "   " : "") text)
		} else if (!GroupInfo.options.countOnly) {
			Ansi.writeLine((!GroupInfo.options.resultOnly
					? "   "
					: "") text)
		}
	}

	readContentFromTempFileAndDeleteIt() {
		content := ""
		GroupInfo.options.tempFile.close()
		tempFile := FileOpen(A_Temp "\__gi__.dat", "r`n")
		content := tempFile.read(tempFile.length)
		tempFile.close()
		if (GroupInfo.options.sort) {
			Sort content
		}
		FileDelete %A_Temp%\__gi__.dat
		return content
	}

	openTempFileIfNecessary() {
		if (GroupInfo.options.sort
				|| GroupInfo.options.output
				|| GroupInfo.options.append) {
			if ((GroupInfo.options.output || GroupInfo.options.append)
					&& GroupInfo.options.color != true) {
				GroupInfo.options.color := false
			}
			GroupInfo.options.tempFile := FileOpen(A_Temp "\__gi__.dat", "w`n")
		}
	}

	tempFileWasNecessary() {
		return IsObject(GroupInfo.options.tempFile)
	}

	distributeTempFileContent() {
		fileName := "*"
		if (GroupInfo.options.append) {
			fileName := GroupInfo.options.append
		} else if (GroupInfo.options.output) {
			fileName := GroupInfo.options.output
			if (FileExist(fileName)) {
				FileDelete %fileName%
			}
		}
		GroupInfo.writeTempFileContent(fileName)
	}

	writeTempFileContent(fileName) {
		content := GroupInfo.readContentFromTempFileAndDeleteIt()
		if (fileName = "*") {
			Ansi.write(content)
		} else {
			FileAppend %content%, %fileName%
		}
	}

	class GroupData {
		searchResult := 0
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
#Include %A_LineFile%\..\modules\ldaptool.ahk
#Include *i %A_ScriptDir%\gi.versioninfo

#Include <modules\structure\LDAPAPIInfo>
#Include <modules\structure\LDAPMod>

Main:
exitapp App.checkRequiredClasses(GroupInfo).run(A_Args) ; notest-end
; vim:tw=0:ts=4:sts=4:sw=4:noet:ft=autohotkey:bomb
