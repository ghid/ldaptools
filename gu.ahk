; ahk: x86
; ahk: console
class GroupUser {

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

	static options := GroupUser.setDefaults()

	static out_file := ""
	static cn := ""
	static dn := ""

	static ldapConnection := 0

	setDefaults() {
		return { append: ""
				, base_dn: ""
				, color: false
				, count: ""
				, countOnly: false
				, filter: "*"
				, groupFilter: "groupOfNames"
				, help: false
				, host: "localhost"
				, ibmNestedGroups: false
				, ignore_case: -1
				, invert_match: false
				, lower: false
				, max_nested_lv: 32
				, output: ""
				, port: 389
				, quiet: false
				, refs: false
				, regex: false
				, result_only: false
				, short: false
				, sort: false
				, tempFile: 0
				, upper: false
				, version: false }
	}

	run(args) {
		try {
			rc := GroupUser.RC_OK
			op := GroupUser.cli()
			args := op.parse(args)
			if (GroupUser.shallHelpOrVersionInfoBeDisplayed()) {
				rc := GroupUser.showHelpOrVersionInfo(op)
			} else {
				GroupUser.evaluateCommandLineOptions(args)
				GroupUser.handleIBMnestedGroups()
				GroupUser.handleParsedArguments(args)
				GroupUser.handleCountOnly()
				rc := GroupUser.handleHitCount(GroupUser.main())
			}
		} catch e {
			OutputDebug % A_ThisFunc ": " e.message " " e.file " #" e.line
			Ansi.writeLine(e.message)
			Ansi.writeLine(op.usage())
			rc := e.Extra
		} finally {
			GroupUser.doCleanup()
		}
		return rc
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
				, GroupUser.options, "ignore_case"
				, "Ignore case when filtering results", OptParser.OPT_NEG
				, GroupUser.options.ignore_case, GroupUser.options.ignore_case))
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
				, GroupUser.options, "invert_match"
				, "Show not matching results"))
		op.add(new OptParser.Boolean(0, "color"
				, GroupUser.options, "color"
				, "Colored output "
				. "(deactivated by default if -a or -o option is set)"
				, OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE, -1, true))
		op.add(new OptParser.Boolean("R", "result-only"
				, GroupUser.options, "result_only"
				, "Suppress any other output than the found groups"))
		op.add(new OptParser.Boolean(0, "ibm-nested-group"
				, GroupUser.options, "ibmNestedGroups"
				, "Only chase groups which implement "
				. "objectclass ibm-nestedGroup"))
		op.add(new OptParser.String(0, "max-nested-level"
				, GroupUser.options, "max_nested_lv", "n"
				, "Defines, which recursion depth terminates the process "
				. "(default=32)"
				,, GroupUser.options.max_nested_lv
				, GroupUser.options.max_nested_lv))
		op.add(new OptParser.Boolean(0, "env"
				, GroupUser.options, "env_dummy"
				, "Ignore environment variable GU_OPTIONS"
				, OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
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

	shallHelpOrVersionInfoBeDisplayed() {
		return GroupUser.options.help || GroupUser.options.version
	}

	showHelpOrVersionInfo(optionParser) {
		if (GroupUser.options.help) {
			Ansi.writeLine(optionParser.usage())
		} else if (GroupUser.options.version) {
			Ansi.writeLine(G_VERSION_INFO.NAME "/"
					. G_VERSION_INFO.ARCH "-b" G_VERSION_INFO.BUILD)
		}
		return ""
	}

	evaluateCommandLineOptions(args) {
		if (args.count() < 1) {
			throw Exception("error: Missing argument"
					,, GroupUser.RC_MISSING_ARG)
		}
		if (args.count() > 2) {
			throw Exception("error: Too many arguments"
					,, GroupUser.RC_TOO_MANY_ARGS)
		}
		if (GroupUser.options.output && GroupUser.options.append) {
			throw Exception("error: Options '-o' and '-a' "
					. "cannot be used together"
					,, GroupUser.RC_INVALID_ARGS)
		}
		if (GroupUser.options.upper && GroupUser.options.lower) {
			throw Exception("error: Options '-l' and '-u' "
					. "cannot be used together"
					,, GroupUser.RC_INVALID_ARGS)
		}
	}

	handleIBMnestedGroups() {
		if (GroupUser.options.ibmNestedGroups) {
			GroupUser.options.groupFilter := "ibm-nestedGroup"
		}
	}

	handleParsedArguments(parsedArguments) {
		GroupUser.cn := parsedArguments[1]
		if (parsedArguments.count() == 2) {
			GroupUser.options.filter := parsedArguments[2]
		}
	}

	handleCountOnly() {
		if (!GroupUser.options.countOnly
				&& !GroupUser.options.result_only) {
			Ansi.writeLine("Connecting to " GroupUser.options.host
					. ":" GroupUser.options.port "...")
		}
	}

	handleHitCount(numberOfHits) {
		if (GroupUser.options.count) {
			Ansi.writeLine("`n" numberOfHits " Hit(s)")
		}
		return numberOfHits
	}

	doCleanup() {
		if (GroupUser.ldapConnection) {
			GroupUser.ldapConnection.unbind()
		}
		if (GroupUser.options.tempFile) {
			GroupUser.options.tempFile.close()
		}
	}

	main() {
		GroupUser.openTempFileIfNecessary()
		GroupUser.connectToLdapServer()
		rc := GroupUser.membersOfGroupsAndSubGroups(GroupUser.cn
				, new GroupUser.MemberData())
		if (GroupUser.tempFileWasNecessary()) {
			GroupUser.distributeTempFileContent()
		}
		return rc
	}

	openTempFileIfNecessary() {
		if (GroupUser.options.sort
				|| GroupUser.options.output
				|| GroupUser.options.append) {
			if ((GroupUser.options.output || GroupUser.options.append)
					&& GroupUser.options.color != true) {
				GroupUser.options.color := false
			}
			GroupUser.options.tempFile := FileOpen(A_Temp "\__gu__.dat", "w`n")
		}
	}

	connectToLdapServer() {
		GroupUser.ldapConnection := new Ldap(GroupUser.options.host
				, GroupUser.options.port)
		GroupUser.ldapConnection.connect()
		GroupUser.ldapConnection.setOption(Ldap.OPT_VERSION, Ldap.VERSION3)
		if (!GroupUser.options.countOnly
				&& !GroupUser.options.result_only) {
			Ansi.writeLine("Ok.")
			Ansi.writeLine(GroupUser.format_output(GroupUser
					.ldap_get_dn("cn=" GroupUser.cn), ""))
		}
	}

	tempFileWasNecessary() {
		return IsObject(GroupUser.options.tempFile)
	}

	distributeTempFileContent() {
		fileName := "*"
		if (GroupUser.options.append) {
			fileName := GroupUser.options.append
		} else if (GroupUser.options.output) {
			fileName := GroupUser.options.output
			if (FileExist(fileName)) {
				FileDelete %fileName%
			}
		}
		GroupUser.writeTempFileContent(fileName)
	}

	writeTempFileContent(fileName) {
		content := GroupUser.readContentFromTempFileAndDeleteIt()
		if (fileName = "*") {
			Ansi.write(content)
		} else {
			FileAppend %content%, %fileName%
		}
	}

	readContentFromTempFileAndDeleteIt() {
		content := ""
		GroupUser.options.tempFile.close()
		h_gu := FileOpen(A_Temp "\__gu__.dat", "r`n")
		content := h_gu.read(h_gu.Length)
		h_gu.close()
		if (GroupUser.options.sort) {
			Sort content
		}
		FileDelete %A_Temp%\__gu__.dat
		return content
	}

	format_output(text, ref) {
		if (GroupUser.options.refs) {
			if (GroupUser.options.short) {
				if (RegExMatch(ref, "^.*?=\s*(.*?)\s*,.*$", $)) {
					ref := $1
				}
			}
		} else {
			ref := ""
		}
		if (GroupUser.options.short) {
			if (RegExMatch(text, "^.*?=\s*(.*?)\s*,.*$", $)) {
				text := $1	
			}
		}
		if (GroupUser.options.upper) {
			text := text.upper()
			ref := ref.upper()
		} else if (GroupUser.options.lower) {
			text := text.lower()
			ref := ref.lower()
		}
		if (GroupUser.options.color) {
			text := RegExReplace(text, "(?P<attr>\w+=)"
					, Ansi.setGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD)
					. "${attr}"
					. Ansi.setGraphic(Ansi.ATTR_OFF))
			if (GroupUser.options.refs && ref != "") {
				ref := Ansi.setGraphic(Ansi.FOREGROUND_RED, Ansi.ATTR_BOLD)
						. "  <-(" RegExReplace(ref, "(?P<attr>\w+=)"
						, Ansi.setGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD)
						. "${attr}"
						. Ansi.setGraphic(Ansi.ATTR_OFF))
						. Ansi.setGraphic(Ansi.FOREGROUND_RED
						, Ansi.ATTR_BOLD) ")"
						. Ansi.setGraphic(Ansi.ATTR_OFF)
			}
		} else {
			if (GroupUser.options.refs) {
				ref := "  <-(" ref ")"
			}
		}
		return text ref
	}

	ldap_get_dn(ldapFilter) {
		if (!GroupUser.ldapConnection.search(searchResult, GroupUser.options.base_dn, ldapFilter)
				== Ldap.LDAP_SUCCESS) {
			throw Exception("error: "
					. Ldap.err2String(GroupUser.ldapConnection.getLastError()))
		}
		if ((iCount := GroupUser.ldapConnection.countEntries(searchResult)) < 0) {
			throw Exception("error: "
					. Ldap.err2String(GroupUser.ldapConnection.getLastError()))
		}
		if (iCount = 0) {
			throw Exception("error: cn not found """ ldapFilter """"
					,, GroupUser.RC_CN_NOT_FOUND)
		} else if (iCount > 1) {
			throw Exception("error: cn is ambigous (" iCount ") """
					. ldapFilter """",, GroupUser.RC_CN_AMBIGOUS)
		}
		entry := GroupUser.ldapConnection.firstEntry(searchResult)
		return GroupUser.ldapConnection.getDn(entry)
	}

	output(text) {
		res := true
		try {
			if (!GroupUser.options.quiet
					&& res := text.filter(GroupUser.options.filter
					, GroupUser.options.regex
					, (GroupUser.options.ignore_case = true ? true : false)
					, GroupUser.options.invert_match)) {
				if (GroupUser.options.tempFile) {
					GroupUser.options.tempFile.writeLine((!GroupUser.options.output
							&& !GroupUser.options.append
							&& !GroupUser.options.result_only ? "	" : "") text)
				} else if (!GroupUser.options.countOnly) {
					Ansi.writeLine((!GroupUser.options.result_only ? "	 ":"")
							. text, true)
				}
			}
		}
		catch _ex {
			OutputDebug % A_ThisFunc ": " _ex.message
			res := false
		}
		return res
	}

	membersOfGroupsAndSubGroups(groupCn, memberData) {
		if (!GroupUser.ldapConnection.search(searchResult, GroupUser.options.base_dn
				, "(&(objectclass=" GroupUser.options.groupFilter ")(cn=" groupCn "))"
				, Ldap.SCOPE_SUBTREE, ["member"])
				== Ldap.LDAP_SUCCESS) {
			throw Exception("error: "
					. Ldap.err2String(GroupUser.ldapConnection.getLastError()))
		}
		if ((iCount := GroupUser.ldapConnection.countEntries(searchResult)) < 0) {
			throw Exception("error: "
					. Ldap.err2String(GroupUser.ldapConnection.getLastError()))
		}
		loop %iCount% {
			if (A_Index = 1) {
				member := GroupUser.ldapConnection.firstEntry(searchResult)
			} else {
				member := GroupUser.ldapConnection.nextEntry(member)
			}
			if (member) {
				pAttr := GroupUser.ldapConnection.firstAttribute(member)
				while (pAttr) {
					System.strCpy(pAttr, stAttr)
					if (stAttr = "member") {
						pValues := GroupUser.ldapConnection.getValues(member, pAttr)
						; aValues := System.ptrListToStrArray(pValues)
						aValues := Structure.ptrListToStrArray(pValues)
						loop % aValues.maxIndex() {
							if (RegExMatch(aValues[A_Index]
									, "i)cn=(.+?)\s*(,.*$|$)", $)) {
								if (GroupUser.ldap_is_group($1)) {
									memberData.nestedLevel++
									if (memberData.nestedLevel>GroupUser.options.max_nested_lv) {
										throw Exception("error: "
												. "Cyclic reference detected: `n`t" $ "`n`t<- " groupCn ; ahklint-ignore: W002
												,, GroupUser.RC_CYCLE_DETECTED)
									}
									GroupUser.membersOfGroupsAndSubGroups($1, memberData)
									memberData.nestedLevel--
								} else {
									if (memberData.memberList[$] = "") {
										if (GroupUser.output(GroupUser.format_output($ ; ahklint-ignore: W002
												, (GroupUser.options.short
												|| !GroupUser.options.refs
												? groupCn
												: GroupUser.ldap_get_dn("cn=" groupCn))))) { ; ahklint-ignore: W002
											memberData.numberOfMembers++
										}
										memberData.memberList[$] := 1
									}
								}
							}
						}
						break
					}
					pAttr := GroupUser.ldapConnection.nextAttribute(member)
				}
			}
		}
		return memberData.numberOfMembers
	}

	ldap_is_group(cn) {
		loop {
			ret := GroupUser.ldapConnection.search(searchResult, GroupUser.options.base_dn
					, "(&(objectclass=" GroupUser.options.groupFilter ")(cn=" cn "))")
		} until (ret != 80)
		if (!ret == Ldap.LDAP_SUCCESS) {
			throw Exception("error: "
					. Ldap.err2String(GroupUser.ldapConnection.getLastError()))
		}
		if (GroupUser.ldapConnection.countEntries(searchResult)) {
			return true
		} else	{
			return false
		}
	}

	class MemberData {
		numberOfMembers := 0
		nestedLevel := 0
		memberList := []
	}
}

#NoEnv ; notest-begin
#MaxHotkeysPerInterval 99000000
#HotkeyInterval 99000000
#KeyHistory 0
ListLines Off
Process, Priority, , H ;if unstable, comment or remove this line
SetBatchLines, -1
SetKeyDelay, -1, -1
SetMouseDelay, -1
SetDefaultMouseSpeed, 0
SetWinDelay, -1
SetControlDelay, -1
SendMode Input

#Include <App>
#Include <cui-libs>
#Include <Ldap>
#Include <System>
#Include *i %A_ScriptDir%\gu.versioninfo

#Include <modules\structure\LDAPAPIInfo>
#Include <modules\structure\LDAPMod>

Ansi.NO_BUFFER := true
exitapp App.checkRequiredClasses(GroupUser).run(A_Args)	; notest-end
; vim:tw=0:ts=4:sts=4:sw=4:noet:ft=autohotkey:bomb
