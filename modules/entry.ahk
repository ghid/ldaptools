class Entry {
	theDn := ""
	theRef := ""
	options := {}

	__new(theDn, theRef, options) {
		this.theDn := theDn
		this.theRef := theRef
		this.options := options
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
			if (this.options.refs) {
				return this.addSeparator(this.handleColor(this
						.handleCase(this.handleShort(this.theRef))))
			}
			return ""
		}
	}

	addSeparator(text) {
		if (this.options.color) {
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
		if (this.options.short) {
			RegExMatch(text, "^.*?=(.*?)\s*,.*$", $)
			return $1
		}
		return text
	}

	handleCase(text) {
		return Format("{:" (this.options.upper ? "U"
				: this.options.lower ? "L"
				: "s") "}", text)
	}

	handleColor(text) {
		if (this.options.color) {
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
