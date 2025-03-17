//
//  ContentView.swift
//  TriviaGame
//
//  Created by Andy Hernandez on 3/16/25.
//

import SwiftUI

struct ContentView: View {
    @State private var numberOfQuestions = 5
    @State private var selectedCategory = "Any"
    @State private var selectedCategoryID: Int? = nil
    @State private var selectedDifficulty = "Any"
    @State private var selectedType = "Multiple Choice"
    @State private var selectedTimer = 30
    @State private var isGameStarted = false
    @State private var categories: [Category] = [Category(id: 0, name: "Any")]

    let difficulties = ["Any", "Easy", "Medium", "Hard"]
    let questionTypes = ["Multiple Choice", "True/False"]
    let timerOptions = [30, 5, 300, 1800]

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Number of Questions")) {
                        Stepper(value: $numberOfQuestions, in: 1...20) {
                            Text("\(numberOfQuestions)")
                        }
                    }

                    Section(header: Text("Category")) {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories) { category in
                                Text(category.name).tag(category.name)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    Section(header: Text("Difficulty")) {
                        Picker("Difficulty", selection: $selectedDifficulty) {
                            ForEach(difficulties, id: \.self) { Text($0) }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    Section(header: Text("Question Type")) {
                        Picker("Type", selection: $selectedType) {
                            ForEach(questionTypes, id: \.self) { Text($0) }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    Section(header: Text("Timer")) {
                        Picker("Timer Duration", selection: $selectedTimer) {
                            ForEach(timerOptions, id: \.self) { Text("\($0) seconds") }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }

                Button(action: {
                    isGameStarted = true
                }) {
                    Text("Start Trivia")
                        .font(.title2)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding()
                }

                NavigationLink(destination: TriviaGameView(numberOfQuestions: numberOfQuestions, category: selectedCategory, categoryID: selectedCategoryID, difficulty: selectedDifficulty, questionType: selectedType, timerDuration: selectedTimer), isActive: $isGameStarted) {
                    EmptyView()
                }
            }
            .navigationTitle("Trivia Options")
            .onAppear {
                fetchCategories()
            }
        }
    }

    func fetchCategories() {
        guard let url = URL(string: "https://opentdb.com/api_category.php") else { return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data {
                do {
                    let response = try JSONDecoder().decode(CategoryResponse.self, from: data)
                    DispatchQueue.main.async {
                        self.categories += response.trivia_categories
                    }
                } catch {
                    print("Failed to decode categories:", error)
                }
            }
        }.resume()
    }
}

struct CategoryResponse: Decodable {
    let trivia_categories: [Category]
}

struct Category: Identifiable, Decodable {
    let id: Int
    let name: String
}

struct TriviaGameView: View {
    let numberOfQuestions: Int
    let category: String
    let categoryID: Int?
    let difficulty: String
    let questionType: String
    let timerDuration: Int

    @State private var questions: [TriviaQuestion] = []
    @State private var currentQuestionIndex = 0
    @State private var selectedAnswer: String? = nil
    @State private var timerRemaining: Int
    @State private var isTimeUp = false
    @State private var score = 0
    @State private var isGameOver = false
    @State private var isAnswerCorrect: Bool? = nil

    init(numberOfQuestions: Int, category: String, categoryID: Int?, difficulty: String, questionType: String, timerDuration: Int){
        self.numberOfQuestions = numberOfQuestions
        self.category = category
        self.categoryID = categoryID
        self.difficulty = difficulty
        self.questionType = questionType
        self.timerDuration = timerDuration
        self._timerRemaining = State(initialValue: timerDuration)
        }

        var body: some View {
            VStack {
                if questions.isEmpty {
                    ProgressView("Loading Questions...")
                        .onAppear { fetchQuestions() }
                } else if isGameOver {
                    ResultsView(score: score, total: numberOfQuestions, onRestart: restartGame)
                } else {
                    Text("Time Remaining: \(timerRemaining) sec")
                        .font(.headline)
                        .padding()

                    CardView(question: questions[currentQuestionIndex], selectedAnswer: $selectedAnswer)
                        .padding()

                    if let isCorrect = isAnswerCorrect {
                        Text(isCorrect ? "Correct!" : "Incorrect :(")
                            .font(.headline)
                            .foregroundColor(isCorrect ? .green : .red)
                            .padding()
                    }

                    Button("Submit Answer") {
                        checkAnswer()
                    }
                    .disabled(selectedAnswer == nil)
                    .padding()
                }
            }
            .navigationTitle("Trivia Game")
            .onAppear {
                startTimer()
            }
        }

        func checkAnswer() {
            if let selected = selectedAnswer {
                if selected == questions[currentQuestionIndex].correctAnswer
                {
                    score += 1
                    isAnswerCorrect = true
                }
                else
                {
                    isAnswerCorrect = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if currentQuestionIndex + 1 < questions.count
                {
                    currentQuestionIndex += 1
                    selectedAnswer = nil
                    isAnswerCorrect = nil
                    timerRemaining = timerDuration
                }
                else
                {
                    isGameOver = true
                }
            }
        }
        func restartGame() {
            score = 0
            currentQuestionIndex = 0
            isGameOver = false
            selectedAnswer = nil
            questions = []
            fetchQuestions()
        }

    func fetchQuestions() {
        guard let url = constructAPIURL() else
        {
            print("Invalid API URL")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching questions: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                let decodedResponse = try JSONDecoder().decode(TriviaResponse.self, from: data)

                DispatchQueue.main.async {
                    self.questions = decodedResponse.results.map { question in
                        TriviaQuestion(
                            text: decodeHTML(question.question),
                            answers: shuffleAnswers(correct: question.correct_answer, incorrect: question.incorrect_answers),
                            correctAnswer: decodeHTML(question.correct_answer)
                        )
                    }
                }
            } catch {
                print("Failed to decode JSON: \(error)")
            }
        }.resume()
    }

    func constructAPIURL() -> URL? {
        var urlString = "https://opentdb.com/api.php?amount=\(numberOfQuestions)"

        if let categoryID = categoryID, categoryID != 0 {
            urlString += "&category=\(categoryID)"
        }

        if difficulty != "Any" {
            urlString += "&difficulty=\(difficulty.lowercased())"
        }

        if questionType == "Multiple Choice" {
            urlString += "&type=multiple"
        } else {
            urlString += "&type=boolean"
        }

        return URL(string: urlString)
    }

    func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if timerRemaining > 0 {
                timerRemaining -= 1
            }
            else
            {
                timer.invalidate()
                if !isGameOver
                {
                    isTimeUp = true
                    checkAnswer()
                }
            }
        }
    }



}
struct TriviaQuestion: Identifiable {
    let id = UUID()
    let text: String
    let answers: [String]
    let correctAnswer: String
}
struct ResultsView: View {
    let score: Int
    let total: Int
    let onRestart: () -> Void

    var body: some View {
        VStack {
            Text("Final Score: \(score)/\(total)")
                .font(.title)
                .padding()

            Button("Play Again") {
                onRestart()
            }
            .padding()
        }
    }
}

struct TriviaResponse: Decodable {
    let results: [APIQuestion]
}

struct CardView: View {
    let question: TriviaQuestion
    @Binding var selectedAnswer: String?
    
    var body: some View {
        VStack {
            Text(question.text)
                .font(.title2)
                .padding()
            
            ForEach(question.answers, id: \..self) { answer in
                Button(action: { selectedAnswer = answer }) {
                    Text(answer)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(selectedAnswer == answer ? Color.green.opacity(0.5) : Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 5)
    }
}

struct APIQuestion: Decodable {
    let question: String
    let correct_answer: String
    let incorrect_answers: [String]
}

func shuffleAnswers(correct: String, incorrect: [String]) -> [String] {
    var options = incorrect + [correct]
    options.shuffle()
    return options.map { decodeHTML($0) }
}

func decodeHTML(_ text: String) -> String {
    guard let data = text.data(using: .utf8) else { return text }
    
    let attributedString = try? NSAttributedString(
        data: data,
        options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
        documentAttributes: nil
    )
    
    return attributedString?.string ?? text
}

