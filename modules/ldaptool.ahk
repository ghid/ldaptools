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

}
