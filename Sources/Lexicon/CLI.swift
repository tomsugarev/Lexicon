//
// github.com/screensailor 2021
//

import Foundation

public struct CLI: Equatable {
    public private(set) var date: Date
    public private(set) var root: Lemma
    public private(set) var breadcrumbs: [Lemma]
    public private(set) var error: Error = .none
    public private(set) var input: String = ""
    public private(set) var suggestions: [Lemma]
    public private(set) var selectedIndex: Int?
}

public extension CLI {
	
	enum Error: Swift.Error, Equatable {
		case none
		case invalidInputCharacter(Character)
		case noChildrenMatchInput(String)
		case invalidSelection(index: Int?)
	}
}

public extension CLI {
	
    init(_ lemma: Lemma, root: Lemma? = nil) async {
        self = await CLI.with(lemma: lemma, root: root)
	}
    
    @LexiconActor
    static func with(lemma: Lemma, root: Lemma? = nil) -> CLI {
        let breadcrumbs = lemma.lineage.reversed()
        var o = CLI(
            date: lemma.lexicon.serialization.date,
            root: root ?? breadcrumbs.first!,
            breadcrumbs: breadcrumbs,
            suggestions: lemma.childrenSortedByType
        )
        o.selectedIndex = o.suggestions.indices.first
        return o
    }
}

public extension CLI {
    
    @inlinable
	var lemma: Lemma {
		breadcrumbs.last!
	}
    
    var selectedSuggestion: Lemma? {
		guard let i = selectedIndex, suggestions.indices ~= i else {
			return nil
		}
        return suggestions[i]
    }
}

public extension CLI {
	
	@discardableResult
	mutating func selectPrevious(cycle: Bool = true) -> Self {
		select(index: (selectedIndex ?? 1) - 1, cycle: cycle)
	}
	
	@discardableResult
	mutating func selectNext(cycle: Bool = true) -> Self {
		select(index: (selectedIndex ?? -1) + 1, cycle: cycle)
	}
	
	@discardableResult
	mutating func select(index: Int, cycle: Bool = false) -> Self {
		if cycle {
			switch (index, suggestions.count)
			{
			case (_, 0):
				error = .invalidSelection(index: index)
				
			case (_, 1):
				error = .none
				selectedIndex = 0
				
			case (...(-1), let count):
				error = .none
				selectedIndex = count + (index % count)
				
			case (0..., let count):
				error = .none
				selectedIndex = index % count
				
			default:
				break
			}
		} else {
			guard suggestions.indices.contains(index) else {
				error = .invalidSelection(index: index)
				return self
			}
			error = .none
			selectedIndex = index
		}
		return self
	}
}

public extension CLI {

    @discardableResult
    mutating func append(_ character: Character) async -> Self {
        self = await CLI.append(character, to: self)
        return self
    }
    
    @LexiconActor
    static func append(_ character: Character, to cli: CLI) -> CLI {
        var o = cli
        o.error = .none
        guard Self.isValid(character: character, appendingTo: o.input) else {
            o.error = .invalidInputCharacter(character)
            return o
        }
        o.input.append(character)
        o.suggestions = o.lemma.suggestions(for: o.input)
        o.selectedIndex = o.suggestions.indices.first
        o.error = o.suggestions.isEmpty ? .noChildrenMatchInput(o.input) : .none
        return o
    }
}

public extension CLI {
    
	@discardableResult
	mutating func replace(input newInput: String) async -> Self {
        self = await CLI.replace(input: newInput, in: self)
        return self
	}
    
    @LexiconActor
    static func replace(input newInput: String, in cli: CLI) -> CLI {
        var o = cli
        o.input = ""
        o.error = .none
        for character in newInput {
            guard Self.isValid(character: character, appendingTo: o.input) else {
                o.error = .invalidInputCharacter(character)
                return o
            }
            o.input.append(character)
        }
        o.suggestions = o.lemma.suggestions(for: o.input)
        o.selectedIndex = o.suggestions.indices.first
        o.error = o.suggestions.isEmpty ? .noChildrenMatchInput(o.input) : .none
        return o
    }
}

public extension CLI {
    
    @discardableResult
    mutating func enter() async -> Self {
        self = await CLI.performEnter(with: self)
        return self
    }
    
    @LexiconActor
    static func performEnter(with cli: CLI) -> CLI {
        var o = cli
        guard
            let index = o.selectedIndex,
            o.suggestions.indices.contains(index)
        else {
            o.error = .invalidSelection(index: o.selectedIndex)
            return o
        }
        o.error = .none
        let suggestion = o.suggestions[index]
        o.breadcrumbs.append(suggestion)
        o.input = ""
        o.suggestions = o.lemma.childrenSortedByType
        o.selectedIndex = o.suggestions.indices.first
        return o
    }
}

public extension CLI {
    
    @discardableResult
    mutating func backspace() async -> Self {
        self = await CLI.performBackspace(with: self)
        return self
    }
    
    @LexiconActor
    static func performBackspace(with cli: CLI) -> CLI {
        var o = cli
        switch (o.breadcrumbs.count, o.input.count)
        {
            case (2..., 0):
                if o.lemma == o.root {
                    return o
                }
                let removed = o.breadcrumbs.removeLast()
                o.suggestions = o.lemma.childrenSortedByType
                o.selectedIndex = o.suggestions.firstIndex(of: removed)
                o.error = .none
                
            case (_, 1...):
                o.input.removeLast()
                o.suggestions = o.lemma.suggestions(for: o.input)
                o.selectedIndex = o.suggestions.indices.first
                if o.input.isEmpty {
                    o.error = .none
                } else {
                    o.error = o.suggestions.isEmpty ? .noChildrenMatchInput(o.input) : .none
                }
                
            default:
                break
        }
        return o
    }
}

public extension CLI {
    
	@discardableResult
	mutating func update(with lexicon: Lexicon? = nil) async -> Self {
        self = await CLI.update(self, with: lexicon)
        return self
	}
    
    @LexiconActor
    static func update(_ cli: CLI, with lexicon: Lexicon? = nil) -> CLI {
        let lexicon = lexicon ?? cli.lemma.lexicon
        var o = cli
        o.date = lexicon.serialization.date
        o.root = lexicon[o.root.id] ?? lexicon.root
        o.breadcrumbs = (lexicon[o.lemma.id] ?? lexicon.root).lineage.reversed()
        o = replace(input: o.input, in: o)
        if let i = o.selectedSuggestion.flatMap(o.suggestions.firstIndex(of:)) {
            o.selectedIndex = i
        }
        return o
    }
}

public extension CLI {
    
    @discardableResult
    mutating func reset(to lemma: Lemma? = nil, selecting: Lemma? = nil) async -> Self {
        self = await CLI.reset(self, to: lemma, selecting: selecting)
        return self
    }
    
    @LexiconActor
    static func reset(_ cli: CLI, to lemma: Lemma? = nil, selecting: Lemma? = nil) -> CLI {
        var o = CLI.with(lemma: lemma ?? cli.lemma)
        if let selecting = selecting, let i = o.suggestions.firstIndex(of: selecting) {
            o.selectedIndex = i
        }
        return o
    }
}

public extension Lemma {
    
    func suggestions(for input: String) -> [Lemma] {
        let input = input.lowercased()
        return childrenSortedByType.filter { child in
            child.name.lowercased().starts(with: input)
        }
    }

    var childrenSortedByType: [Lemma] {
		var o = ownChildren.values.sorted(by: \.name)
		for type in ownType.values.sorted(by: \.id) {
			o.append(contentsOf: type.children.keys.sorted(by: \.self).compactMap{ children[$0] })
        }
        return o
    }

    var childrenGroupedByTypeAndSorted: [(type: Lemma, children: [Lemma])] {
		var o = [(self, ownChildren.values.sorted(by: \.name))]
		for type in ownType.values.sorted(by: \.id) {
			o.append((type.unwrapped, type.children.keys.sorted(by: \.self).compactMap{ children[$0] }))
        }
        return o
    }
}

public extension CLI {
	
	static func isValid(character: Character, appendingTo input: String)  -> Bool {
		CharacterSet(charactersIn: String(character)).isSubset(
			of: input.isEmpty
				? Lemma.validFirstCharacterOfName
				: Lemma.validCharacterOfName
		)
	}
}

extension CLI: CustomStringConvertible {
	
	public var description: String {
		if input.isEmpty {
			return lemma.description
		} else {
			return "\(lemma)\(error == .none ? "?" : "+")\(input)"
		}
	}
}
