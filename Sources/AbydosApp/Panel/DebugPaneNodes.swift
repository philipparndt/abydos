import AppKit
import AbydosKit

/// The rows of the variables tree, which is three kinds of thing drawn as one.
///
/// A scope's variables are addressed by scope and path, a watch's by the
/// watch's id and a path under it. Keeping the owner on every node is what lets
/// one outline view hold both, and what lets a row be found again after a
/// refresh has replaced every object in the tree.
extension DebugPane {

	/// What a variable hangs off, which decides who is asked to open it.
	///
	/// A scope's variables are addressed by scope and path; a watch's are
	/// addressed by the watch's id and a path under it. Same rows, same cells,
	/// two roots — and the root is the only thing that differs, so it is the
	/// only thing this says.
	enum VariableOwner {
		case scope(Int)
		case watch(UUID)
	}

	/// Flattened variable tree for the outline view.
	final class VariableNode {
		let variable: Variable
		let owner: VariableOwner
		let path: [Int]
		var children: [VariableNode] = []

		init(variable: Variable, owner: VariableOwner, path: [Int]) {
			self.variable = variable
			self.owner = owner
			self.path = path
		}
	}

	/// A watched expression in the tree, above the scopes.
	final class WatchNode {
		let watch: WatchExpression
		var children: [VariableNode] = []
		init(watch: WatchExpression) { self.watch = watch }
	}

	final class ScopeNode {
		let scope: Scope
		let index: Int
		var children: [VariableNode] = []

		init(scope: Scope, index: Int) {
			self.scope = scope
			self.index = index
		}
	}
}
