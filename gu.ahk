; ahk: x86
; ahk: console
class GroupUser extends LdapTool {

	requires() {
		return [Ansi, Arrays, Ldap, Object, OptParser, String, System]
	}

	#Include %A_LineFile%\..\modules
	#Include entry.ahk

	static options := {}

	static cn := ""
	static tempFileName := A_Temp "\__gu__.dat"

	setDefaults() {
		GroupUser.options := Object.append(base.options.clone()
				, {invertMatch: false})
	}

	run(commandLineArguments) {
		try {
			GroupUser.setDefaults()
			returnCode := GroupUser.RC_OK
			optionParser := GroupUser.cli()
			parsedArguments := optionParser.parse(commandLineArguments)
			if (GroupUser.shallHelpOrVersionInfoBeDisplayed()) {
				returnCode := GroupUser.showHelpOrVersionInfo(optionParser)
			} else {
				GroupUser.evaluateCommandLineOptions(parsedArguments)
				GroupUser.handleIBMnestedGroups()
				GroupUser.handleParsedArguments(parsedArguments)
				GroupUser.handleCountOnly()
				returnCode := GroupUser.handleHitCount(GroupUser.main())
			}
		} catch gotException {
			OutputDebug % gotException.what
					. "`nin: " gotException.file " #" gotException.line
			Ansi.writeLine(gotException.message)
			Ansi.writeLine(optionParser.usage())
			returnCode := gotException.extra
		} finally {
			GroupUser.doCleanup()
		}
		return returnCode
	}

	cli() {
		op := new OptParser("gu [-a <filename> | -o <filename>] [options] "
				. "<cn> [filter]",, "GU_OPTIONS")
		op.add(new OptParser.String("a", "append"
				, GroupUser.options, "append", "file-name"
				, "Append result to existing file"))
		op.add(new OptParser.String("o", ""
				, GroupUser.options, "output", "file-name"
				, "Write result to file"))
		op.add(new OptParser.Group("`nOptions"))
		op.add(new OptParser.Boolean("1", "short"
				, GroupUser.options, "short"
				, "Display common names instead of the DN"))
		op.add(new OptParser.Boolean("c", "count"
				, GroupUser.options, "count"
				, "Display number of hits"))
		op.add(new OptParser.Boolean("C", "count-only"
				, GroupUser.options, "countOnly"
				, "Return the number of hits as exit code; no other output"))
		op.add(new OptParser.Boolean("e", "regex"
				, GroupUser.options, "regex"
				, "Use a regular expression to filter the result set "
				. "(see also "
				. "http://ahkscript.org/docs/misc/RegEx-QuickRef.htm)"))
		op.add(new OptParser.String("h", "host"
				, GroupUser.options, "host", "host-name"
				, "Hostname of the LDAP-Server (default="
				. GroupUser.options.host ")"
				,, GroupUser.options.host, GroupUser.options.host))
		op.add(new OptParser.String("p", "port"
				, GroupUser.options, "port", "portnum"
				, "Port number of the LDAP-Server (default="
				. GroupUser.options.port ")"
				,, GroupUser.options.port, GroupUser.options.port))
		op.add(new OptParser.Boolean("i", "ignore-case"
				, GroupUser.options, "ignoreCase"
				, "Ignore case when filtering results", OptParser.OPT_NEG
				, GroupUser.options.ignoreCase, GroupUser.options.ignoreCase))
		op.add(new OptParser.Boolean("l", "lower"
				, GroupUser.options, "lower"
				, "Display result in lower case characters"))
		op.add(new OptParser.Boolean("u", "upper"
				, GroupUser.options, "upper"
				, "Display result in upper case characters"))
		op.add(new OptParser.Boolean("r", "refs"
				, GroupUser.options, "refs"
				, "Display relations"))
		op.add(new OptParser.Boolean("s", "sort"
				, GroupUser.options, "sort"
				, "Sort result"))
		op.add(new OptParser.Boolean("v", "invert-match"
				, GroupUser.options, "invertMatch"
				, "Show not matching results"))
		op.add(new OptParser.Boolean(0, "color"
				, GroupUser.options, "color"
				, "Colored output "
				. "(deactivated by default if -a or -o option is set)"
				, OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE, -1, true))
		op.add(new OptParser.Boolean("R", "result-only"
				, GroupUser.options, "resultOnly"
				, "Suppress any other output than the found groups"))
		op.add(new OptParser.Boolean(0, "ibm-nested-group"
				, GroupUser.options, "ibmNestedGroups"
				, "Only chase groups which implement "
				. "objectclass ibm-nestedGroup"))
		op.add(new OptParser.String(0, "max-nested-level"
				, GroupUser.options, "maxNestedLevel", "n"
				, "Defines, which recursion depth terminates the process "
				. "(default=32)"
				,, GroupUser.options.maxNestedLevel
				, GroupUser.options.maxNestedLevel))
		op.add(new OptParser.Line("--[no]env"
				, "Ignore environment variable GU_OPTIONS"))
		op.add(new OptParser.Boolean("q", "quiet"
				, GroupUser.options, "quiet"
				, "Suppress output of results"))
		op.add(new OptParser.Boolean(0, "version"
				, GroupUser.options, "version"
				, "Print version info"))
		op.add(new OptParser.Boolean(0, "help"
				, GroupUser.options, "help"
				, "Print help", OptParser.OPT_HIDDEN))
		return op
	}

	main() {
		GroupUser.openTempFileIfNecessary()
		GroupUser.connectToLdapServer()
		GroupUser.printDn()
		numberOfHits := GroupUser.membersOfGroupsAndSubGroups(GroupUser.cn
				, new GroupUser.MemberData())
		if (GroupUser.tempFileWasNecessary()) {
			GroupUser.distributeTempFileContent()
		}
		return numberOfHits
	}

	filterOutput(entry) {
		if (isDnMatchingTheFilter
				:= entry.handleCase(entry.handleShort(entry.theDn))
				.filter(GroupUser.options.filter, GroupUser.options.regex
				, (GroupUser.options.ignoreCase = true ? true : false)
				, GroupUser.options.invertMatch)) {
			GroupUser.writeOutput(entry.toString())
		}
		return isDnMatchingTheFilter
	}

	membersOfGroupsAndSubGroups(groupCn, memberData) {
		ldapFilter := Format("(&(objectclass={:s})(cn={:s}))"
				, GroupUser.options.filterObjectClass, groupCn)
		if (!GroupUser.ldapConnection.search(searchResult
				, GroupUser.options.baseDn, ldapFilter
				, Ldap.SCOPE_SUBTREE, ["member"]) == Ldap.LDAP_SUCCESS) {
			throw Exception("error: "
					. Ldap.err2String(GroupUser.ldapConnection.getLastError()))
		}
		numberOfEntriesFound := GroupUser.checkNumberOfEntries(searchResult)
		loop %numberOfEntriesFound% {
			member := (A_Index == 1
					? GroupUser.ldapConnection.firstEntry(searchResult)
					: GroupUser.ldapConnection.nextEntry(member))
			if (member) {
				pAttr := GroupUser.ldapConnection.firstAttribute(member)
				while (pAttr) {
					pValues := GroupUser.ldapConnection.getValues(member, pAttr)
					aValues := System.ptrListToStrArray(pValues, false)
					GroupUser.processMembersOfGroup(memberData, groupCn
							, aValues)
					pAttr := GroupUser.ldapConnection.nextAttribute(member)
				}
			}
		}
		return memberData.numberOfMembers
	}

	processMembersOfGroup(memberData, groupCn, aValues) {
		Arrays.forEach(aValues
				, GroupUser.resolveGroupOrFillMemberList.bind(GroupUser
				, memberData, groupCn))
	}

	resolveGroupOrFillMemberList(memberData, groupCn, memberDn) {
		if (GroupUser.isDnAGroup(memberDn)) {
			GroupUser.resolveGroup(memberData, memberDn
					, GroupUser.getCnOfMemberDn(memberDn))
		} else {
			GroupUser.fillMemberList(memberData, memberDn, groupCn)
		}
	}

	isDnAGroup(dn) {
		cn := GroupUser.getCnOfMemberDn(dn)
		ret := GroupUser.ldapConnection.search(searchResult
				, GroupUser.options.baseDn
				, "(&(objectclass=" GroupUser.options.filterObjectClass
				. ")(cn=" cn "))")
		if (!ret == Ldap.LDAP_SUCCESS) {
			throw Exception("error: "
					. Ldap.err2String(GroupUser.ldapConnection.getLastError()))
		}
		if (cn && GroupUser.ldapConnection.countEntries(searchResult)) {
			return true
		} else	{
			return false
		}
	}

	getCnOfMemberDn(memberDn) {
		RegExMatch(memberDn, "i)cn=(.+?)\s*(,.*$|$)", $)
		return $1
	}

	resolveGroup(memberData, memberDn, groupCn) {
		memberData.nestedLevel++
		if (memberData.nestedLevel
				> GroupUser.options.maxNestedLevel) {
			throw Exception("error: "
					. "Cyclic reference detected: `n`t"
					. memberDn "`n`t<- " groupCn
					,, GroupUser.RC_CYCLE_DETECTED)
		}
		GroupUser.membersOfGroupsAndSubGroups(GroupUser
				.getCnOfMemberDn(memberDn), memberData)
		memberData.nestedLevel--
	}

	fillMemberList(memberData, memberDn, groupCn) {
		if (memberData.memberList[memberDn] = "") {
			if (GroupUser.processOutput(new GroupUser.Entry(memberDn
					, (GroupUser.options.short
					? groupCn : GroupUser.findDnByFilter("cn=" groupCn))
					, GroupUser.options))) {
				memberData.numberOfMembers++
			}
			memberData.memberList[memberDn] := 1
		}
	}

	class MemberData {
		numberOfMembers := 0
		nestedLevel := 0
		memberList := []
	}
}

#NoEnv ; notest-begin
if (!A_IsCompiled) {
	#Warn All, StdOut
}
ListLines Off
Process, Priority, , H ;if unstable, comment or remove this line
SetBatchLines, -1

#Include <App>
#Include <cui-libs>
#Include <Ldap>
#Include <System>
#Include %A_LineFile%\..\modules\ldaptool.ahk
#Include *i %A_ScriptDir%\gu.versioninfo

#Include <modules\structure\LDAPAPIInfo>
#Include <modules\structure\LDAPMod>

Ansi.NO_BUFFER := true
exitapp App.checkRequiredClasses(GroupUser).run(A_Args)	; notest-end
; vim:tw=0:ts=4:sts=4:sw=4:noet:ft=autohotkey:bomb
