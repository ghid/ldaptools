class LdapTool {

	static RC_OK := -1
	static RC_MISSING_ARG := -2
	static RC_INVALID_ARGS := -3
	static RC_CYCLE_DETECTED := -4
	static RC_CN_NOT_FOUND := -5
	static RC_CN_AMBIGOUS := -6
	static RC_TOO_MANY_ARGS := -7

	static ldapConnection := 0

	static options := LdapTool.setDefaults()

	setDefaults() {
		return { append: ""
				, baseDn: ""
				, color: false
				, count: ""
				, countOnly: false
				, filter: "*"
				, filterObjectClass: "groupOfNames"
				, group: ""
				, help: false
				, host: "localhost"
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

	shallHelpOrVersionInfoBeDisplayed() {
		return this.options.help || this.options.version
	}

	showHelpOrVersionInfo(optionParser) {
		if (this.options.help) {
			Ansi.writeLine(optionParser.usage())
		} else if (this.options.version) {
			Ansi.writeLine(G_VERSION_INFO.NAME "/"
					. G_VERSION_INFO.ARCH "-b" G_VERSION_INFO.BUILD)
		}
		return ""
	}

	evaluateCommandLineOptions(args) {
		if (args.count() < 1) {
			throw Exception("error: Missing argument"
					,, this.RC_MISSING_ARG)
		}
		if (args.count() > 2) {
			throw Exception("error: Too many arguments"
					,, this.RC_TOO_MANY_ARGS)
		}
		if (this.options.output && this.options.append) {
			throw Exception("error: Options '-o' and '-a' "
					. "cannot be used together"
					,, this.RC_INVALID_ARGS)
		}
		if (this.options.upper && this.options.lower) {
			throw Exception("error: Options '-l' and '-u' "
					. "cannot be used together"
					,, this.RC_INVALID_ARGS)
		}
	}

	handleParsedArguments(parsedArguments) {
		this.cn := parsedArguments[1]
		if (parsedArguments.count() == 2) {
			this.options.filter := parsedArguments[2]
		}
	}

	handleIBMnestedGroups() {
		if (this.options.ibmNestedGroups) {
			this.options.filterObjectClass := "ibm-nestedGroup"
		}
	}

	handleCountOnly() {
		if (!this.options.countOnly && !this.options.resultOnly) {
			Ansi.write("`nConnecting to " this.options.host
					. ":" this.options.port " ... ")
		}
	}

	handleHitCount(numberOfHits) {
		if (this.options.count) {
			Ansi.writeLine("`n" numberOfHits " Hit(s)")
		}
		return numberOfHits
	}

	connectToLdapServer() {
		this.ldapConnection := new Ldap(this.options.host, this.options.port)
		this.ldapConnection.setOption(Ldap.OPT_VERSION, Ldap.VERSION3)
		this.ldapConnection.connect()
		if (!this.options.countOnly && !this.options.resultOnly) {
			Ansi.writeLine("Ok.")
		}
	}

	openTempFileIfNecessary() {
		if (this.options.sort
				|| this.options.output
				|| this.options.append) {
			if ((this.options.output || this.options.append)
					&& this.options.color != true) {
				this.options.color := false
			}
			this.options.tempFile := FileOpen(this.tempFileName, "w`n")
		}
	}

	distributeTempFileContent() {
		fileName := "*"
		if (this.options.append) {
			fileName := this.options.append
		} else if (this.options.output) {
			fileName := this.options.output
			if (FileExist(fileName)) {
				FileDelete %fileName%
			}
		}
		this.writeTempFileContent(fileName)
	}

	writeTempFileContent(fileName) {
		content := this.readContentFromTempFileAndDeleteIt()
		if (fileName = "*") {
			Ansi.write(content)
		} else {
			FileAppend %content%, %fileName%
		}
	}

	readContentFromTempFileAndDeleteIt() {
		content := ""
		this.options.tempFile.close()
		tempFile := FileOpen(this.tempFileName, "r`n")
		content := tempFile.read(tempFile.length)
		tempFile.close()
		if (this.options.sort) {
			Sort content
		}
		FileDelete % this.tempFileName
		return content
	}

	tempFileWasNecessary() {
		return IsObject(this.options.tempFile)
	}

	doCleanup() {
		if (this.ldapConnection) {
			this.ldapConnection.unbind()
		}
		if (this.options.tempFile) {
			this.options.tempFile.close()
		}
	}
}
