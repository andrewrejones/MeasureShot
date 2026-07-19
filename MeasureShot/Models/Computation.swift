import Foundation

struct MSComputationVariable: Identifiable, Hashable {
    let id: String
    let sourceID: String
    let sourceTitle: String
    let metricID: String
    let metricTitle: String
    let value: Double
    let unit: String

    var title: String {
        "\(sourceTitle) \(metricTitle) (\(unit))"
    }
}

struct MSComputationResult: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var expression: String
    var value: Double
    var formattedValue: String
    var createdAt = Date()

    var exportLine: String {
        "\(name): \(formattedValue) = \(expression)"
    }
}

enum MSFormulaEvaluationError: LocalizedError {
    case emptyExpression
    case unknownVariable(String)
    case invalidToken(String)
    case mismatchedParentheses
    case missingOperand
    case divisionByZero
    case invalidExpression

    var errorDescription: String? {
        switch self {
        case .emptyExpression:
            return "Enter an equation."
        case .unknownVariable(let variable):
            return "Unknown value: \(variable)."
        case .invalidToken(let token):
            return "Invalid token: \(token)."
        case .mismatchedParentheses:
            return "Check the brackets."
        case .missingOperand:
            return "The equation is missing a number or value."
        case .divisionByZero:
            return "Cannot divide by zero."
        case .invalidExpression:
            return "The equation is not complete."
        }
    }
}

enum MSFormulaEvaluator {
    private enum Token: Equatable {
        case number(Double)
        case variable(String)
        case operation(Character)
        case openParenthesis
        case closeParenthesis
    }

    static func evaluate(expression: String, variables: [String: Double]) throws -> Double {
        let tokens = try tokenize(expression)
        guard !tokens.isEmpty else { throw MSFormulaEvaluationError.emptyExpression }

        let postfix = try makePostfix(tokens)
        return try evaluatePostfix(postfix, variables: variables)
    }

    private static func tokenize(_ expression: String) throws -> [Token] {
        let characters = Array(expression)
        var tokens: [Token] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                index += 1
                continue
            }

            if character.isNumber || character == "." {
                let start = index
                index += 1
                while index < characters.count,
                      characters[index].isNumber || characters[index] == "." {
                    index += 1
                }

                let valueText = String(characters[start..<index])
                guard let value = Double(valueText) else {
                    throw MSFormulaEvaluationError.invalidToken(valueText)
                }
                tokens.append(.number(value))
                continue
            }

            if character.isLetter {
                let start = index
                index += 1
                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber || characters[index] == "." || characters[index] == "_" {
                    index += 1
                }

                tokens.append(.variable(String(characters[start..<index])))
                continue
            }

            switch character {
            case "+", "-", "*", "×", "/", "÷":
                if character == "-", shouldTreatMinusAsUnary(after: tokens.last) {
                    tokens.append(.number(0))
                }
                tokens.append(.operation(normalizedOperator(character)))
                index += 1
            case "(":
                tokens.append(.openParenthesis)
                index += 1
            case ")":
                tokens.append(.closeParenthesis)
                index += 1
            default:
                throw MSFormulaEvaluationError.invalidToken(String(character))
            }
        }

        return tokens
    }

    private static func shouldTreatMinusAsUnary(after token: Token?) -> Bool {
        guard let token else { return true }

        switch token {
        case .operation, .openParenthesis:
            return true
        case .number, .variable, .closeParenthesis:
            return false
        }
    }

    private static func normalizedOperator(_ character: Character) -> Character {
        switch character {
        case "×": return "*"
        case "÷": return "/"
        default: return character
        }
    }

    private static func makePostfix(_ tokens: [Token]) throws -> [Token] {
        var output: [Token] = []
        var operations: [Token] = []

        for token in tokens {
            switch token {
            case .number, .variable:
                output.append(token)
            case .operation(let currentOperation):
                while let last = operations.last,
                      case .operation(let previousOperation) = last,
                      precedence(previousOperation) >= precedence(currentOperation) {
                    output.append(operations.removeLast())
                }
                operations.append(token)
            case .openParenthesis:
                operations.append(token)
            case .closeParenthesis:
                var foundOpeningParenthesis = false

                while let last = operations.popLast() {
                    if last == .openParenthesis {
                        foundOpeningParenthesis = true
                        break
                    }
                    output.append(last)
                }

                if !foundOpeningParenthesis {
                    throw MSFormulaEvaluationError.mismatchedParentheses
                }
            }
        }

        while let token = operations.popLast() {
            if token == .openParenthesis || token == .closeParenthesis {
                throw MSFormulaEvaluationError.mismatchedParentheses
            }
            output.append(token)
        }

        return output
    }

    private static func evaluatePostfix(_ tokens: [Token], variables: [String: Double]) throws -> Double {
        var stack: [Double] = []

        for token in tokens {
            switch token {
            case .number(let value):
                stack.append(value)
            case .variable(let name):
                guard let value = variables[name] else {
                    throw MSFormulaEvaluationError.unknownVariable(name)
                }
                stack.append(value)
            case .operation(let operation):
                guard let right = stack.popLast(), let left = stack.popLast() else {
                    throw MSFormulaEvaluationError.missingOperand
                }

                switch operation {
                case "+":
                    stack.append(left + right)
                case "-":
                    stack.append(left - right)
                case "*":
                    stack.append(left * right)
                case "/":
                    guard right != 0 else { throw MSFormulaEvaluationError.divisionByZero }
                    stack.append(left / right)
                default:
                    throw MSFormulaEvaluationError.invalidToken(String(operation))
                }
            case .openParenthesis, .closeParenthesis:
                throw MSFormulaEvaluationError.invalidExpression
            }
        }

        guard stack.count == 1, let result = stack.first else {
            throw MSFormulaEvaluationError.invalidExpression
        }

        return result
    }

    private static func precedence(_ operation: Character) -> Int {
        switch operation {
        case "+", "-": return 1
        case "*", "/": return 2
        default: return 0
        }
    }
}
