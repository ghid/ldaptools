class Entry {
	theDn := ""
	theRef := ""

	__new(theDn, theRef) {
		this.theDn := theDn
		this.theRef := theRef
		return this
	}

	dn[] {
		get {
			return this.handleColor(this.handleCase(this
					.handleShort(this.theDn)))
		}
	}

	ref[] {
		get {
			if (GroupInfo.options.refs) {
				return this.addSeparator(this.handleColor(this
						.handleCase(this.handleShort(this.theRef))))
			}
			return ""
		}
	}

	addSeparator(text) {
		if (GroupInfo.options.color) {
			beginSeparator := Ansi.setGraphic(Ansi.FOREGROUND_RED
					, Ansi.ATTR_BOLD)
			endSeparator := Ansi.setGraphic(Ansi.ATTR_OFF)
		} else {
			beginSeparator := ""
			endSeparator := ""
		}
		return Format("{:s}  <-({:s}{:s}){:s}"
				, beginSeparator, text, beginSeparator, endSeparator)
	}

	handleShort(text) {
		if (GroupInfo.options.short) {
			RegExMatch(text, "^.*?=(.*?)\s*,.*$", $)
			return $1
		}
		return text
	}

	handleCase(text) {
		return Format("{:" (GroupInfo.options.upper ? "U"
				: GroupInfo.options.lower ? "L"
				: "s") "}", text)
	}

	handleColor(text) {
		if (GroupInfo.options.color) {
			return RegExReplace(text, "(?P<attr>\w+=)"
					, Ansi.setGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD)
					. "${attr}"
					. Ansi.setGraphic(Ansi.ATTR_OFF))
		}
		return text
	}

	toString() {
		return this.dn this.ref
	}
}
