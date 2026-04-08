import UIKit

// MARK: - App Theme

struct AppTheme {
    let primary: UIColor
    let background: UIColor
    let surface: UIColor
    let textPrimary: UIColor
    let textSecondary: UIColor
    let error: UIColor
    let border: UIColor
    let inputBackground: UIColor

    #if THEME_BRANDED
    static let current = AppTheme(
        primary: UIColor(red: 0x63/255.0, green: 0x66/255.0, blue: 0xF1/255.0, alpha: 1),     // #6366F1
        background: UIColor(red: 0xF8/255.0, green: 0xFA/255.0, blue: 0xFC/255.0, alpha: 1),   // #F8FAFC
        surface: .white,
        textPrimary: UIColor(red: 0x0F/255.0, green: 0x17/255.0, blue: 0x2A/255.0, alpha: 1),  // #0F172A
        textSecondary: UIColor(red: 0x64/255.0, green: 0x74/255.0, blue: 0x8B/255.0, alpha: 1),// #64748B
        error: UIColor(red: 0xEF/255.0, green: 0x44/255.0, blue: 0x44/255.0, alpha: 1),        // #EF4444
        border: UIColor(red: 0xE2/255.0, green: 0xE8/255.0, blue: 0xF0/255.0, alpha: 1),       // #E2E8F0
        inputBackground: UIColor(red: 0xF1/255.0, green: 0xF5/255.0, blue: 0xF9/255.0, alpha: 1) // #F1F5F9
    )
    #else
    static let current = AppTheme(
        primary: .systemBlue,
        background: .systemGroupedBackground,
        surface: .systemBackground,
        textPrimary: .label,
        textSecondary: .secondaryLabel,
        error: .systemRed,
        border: .separator,
        inputBackground: .secondarySystemBackground
    )
    #endif
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UINavigationController(rootViewController: TaskManagerViewController())
        window?.makeKeyAndVisible()
        return true
    }
}

// MARK: - Task Model

struct Task {
    let id: UUID
    var title: String
    var isCompleted: Bool

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
    }
}

// MARK: - Filter

enum TaskFilter: Int, CaseIterable {
    case all, active, completed

    var title: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .completed: return "Completed"
        }
    }
}

// MARK: - Task Cell

class TaskCell: UITableViewCell {
    static let reuseID = "TaskCell"

    var onToggle: (() -> Void)?
    var onDelete: (() -> Void)?

    private let checkButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let deleteButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        checkButton.translatesAutoresizingMaskIntoConstraints = false
        checkButton.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)
        checkButton.tintColor = AppTheme.current.primary
        contentView.addSubview(checkButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.numberOfLines = 0
        contentView.addSubview(titleLabel)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = AppTheme.current.error
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        contentView.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            checkButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            checkButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkButton.widthAnchor.constraint(equalToConstant: 32),
            checkButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: checkButton.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            deleteButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            deleteButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 32),
            deleteButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    func configure(with task: Task) {
        titleLabel.text = task.title
        let iconName = task.isCompleted ? "checkmark.circle.fill" : "circle"
        checkButton.setImage(UIImage(systemName: iconName), for: .normal)
        checkButton.tintColor = task.isCompleted ? .systemGreen : AppTheme.current.textSecondary

        if task.isCompleted {
            titleLabel.textColor = AppTheme.current.textSecondary
            titleLabel.attributedText = NSAttributedString(
                string: task.title,
                attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .foregroundColor: AppTheme.current.textSecondary]
            )
        } else {
            titleLabel.textColor = AppTheme.current.textPrimary
            titleLabel.attributedText = nil
            titleLabel.text = task.title
        }
    }

    @objc private func toggleTapped() { onToggle?() }
    @objc private func deleteTapped() { onDelete?() }
}

// MARK: - View Controller

class TaskManagerViewController: UIViewController {
    private var tasks: [Task] = []
    private var currentFilter: TaskFilter = .all

    private let inputField = UITextField()
    private let addButton = UIButton(type: .system)
    private let tableView = UITableView()
    private let filterControl = UISegmentedControl(items: TaskFilter.allCases.map { $0.title })
    private let clearButton = UIButton(type: .system)
    private let emptyLabel = UILabel()

    private var filteredTasks: [Task] {
        switch currentFilter {
        case .all: return tasks
        case .active: return tasks.filter { !$0.isCompleted }
        case .completed: return tasks.filter { $0.isCompleted }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tasks"
        view.backgroundColor = AppTheme.current.background
        navigationController?.navigationBar.prefersLargeTitles = true
        setupInputBar()
        setupTableView()
        setupBottomBar()
        updateEmptyState()
    }

    // MARK: - Input Bar

    private func setupInputBar() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = AppTheme.current.surface
        view.addSubview(container)

        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.placeholder = "What needs to be done?"
        inputField.borderStyle = .none
        inputField.backgroundColor = AppTheme.current.inputBackground
        inputField.layer.cornerRadius = 10
        inputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        inputField.leftViewMode = .always
        inputField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        inputField.rightViewMode = .always
        inputField.returnKeyType = .done
        inputField.delegate = self
        container.addSubview(inputField)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        addButton.tintColor = AppTheme.current.primary
        addButton.contentVerticalAlignment = .fill
        addButton.contentHorizontalAlignment = .fill
        addButton.addTarget(self, action: #selector(addTask), for: .touchUpInside)
        container.addSubview(addButton)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = AppTheme.current.border
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            inputField.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            inputField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            inputField.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            inputField.heightAnchor.constraint(equalToConstant: 44),

            addButton.leadingAnchor.constraint(equalTo: inputField.trailingAnchor, constant: 12),
            addButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            addButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 36),
            addButton.heightAnchor.constraint(equalToConstant: 36),

            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        // Store container reference for table view layout
        container.tag = 100
    }

    // MARK: - Table View

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = AppTheme.current.background
        tableView.register(TaskCell.self, forCellReuseIdentifier: TaskCell.reuseID)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 60, bottom: 0, right: 0)
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No tasks yet.\nTap + to add one."
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .tertiaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .title3)
        emptyLabel.numberOfLines = 0
        view.addSubview(emptyLabel)

        guard let inputContainer = view.viewWithTag(100) else { return }

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])
    }

    // MARK: - Bottom Bar

    private func setupBottomBar() {
        let bottomContainer = UIView()
        bottomContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomContainer.backgroundColor = AppTheme.current.surface
        view.addSubview(bottomContainer)

        let topSep = UIView()
        topSep.translatesAutoresizingMaskIntoConstraints = false
        topSep.backgroundColor = AppTheme.current.border
        bottomContainer.addSubview(topSep)

        filterControl.translatesAutoresizingMaskIntoConstraints = false
        filterControl.selectedSegmentIndex = 0
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        bottomContainer.addSubview(filterControl)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setTitle("Clear Completed", for: .normal)
        clearButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        clearButton.tintColor = AppTheme.current.error
        clearButton.addTarget(self, action: #selector(clearCompleted), for: .touchUpInside)
        bottomContainer.addSubview(clearButton)

        NSLayoutConstraint.activate([
            tableView.bottomAnchor.constraint(equalTo: bottomContainer.topAnchor),

            bottomContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            topSep.topAnchor.constraint(equalTo: bottomContainer.topAnchor),
            topSep.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            topSep.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            topSep.heightAnchor.constraint(equalToConstant: 0.5),

            filterControl.topAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: 10),
            filterControl.centerXAnchor.constraint(equalTo: bottomContainer.centerXAnchor),

            clearButton.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 8),
            clearButton.centerXAnchor.constraint(equalTo: bottomContainer.centerXAnchor),
            clearButton.bottomAnchor.constraint(equalTo: bottomContainer.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Actions

    @objc private func addTask() {
        guard let text = inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        tasks.append(Task(title: text))
        inputField.text = ""
        inputField.resignFirstResponder()
        tableView.reloadData()
        updateEmptyState()
    }

    @objc private func filterChanged() {
        currentFilter = TaskFilter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        tableView.reloadData()
        updateEmptyState()
    }

    @objc private func clearCompleted() {
        tasks.removeAll { $0.isCompleted }
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        let empty = filteredTasks.isEmpty
        emptyLabel.isHidden = !empty
        tableView.isHidden = empty

        if empty {
            switch currentFilter {
            case .all:
                emptyLabel.text = "No tasks yet.\nTap + to add one."
            case .active:
                emptyLabel.text = "No active tasks.\nAll done!"
            case .completed:
                emptyLabel.text = "No completed tasks yet."
            }
        }

        clearButton.isEnabled = tasks.contains { $0.isCompleted }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }
}

// MARK: - UITableViewDataSource & Delegate

extension TaskManagerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredTasks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TaskCell.reuseID, for: indexPath) as! TaskCell
        let task = filteredTasks[indexPath.row]
        cell.configure(with: task)

        cell.onToggle = { [weak self] in
            guard let self = self else { return }
            if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                self.tasks[idx].isCompleted.toggle()
                tableView.reloadData()
                self.updateEmptyState()
            }
        }

        cell.onDelete = { [weak self] in
            guard let self = self else { return }
            if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                self.tasks.remove(at: idx)
                tableView.reloadData()
                self.updateEmptyState()
            }
        }

        return cell
    }
}

// MARK: - UITextFieldDelegate

extension TaskManagerViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        addTask()
        return true
    }
}
