import UIKit

// MARK: - App Theme

struct AppTheme {
    let primary: UIColor
    let background: UIColor
    let surface: UIColor
    let textPrimary: UIColor
    let textSecondary: UIColor
    let textDisabled: UIColor
    let error: UIColor
    let border: UIColor
    let inputBackground: UIColor

    #if THEME_BRANDED || THEME_BASELINE || THEME_NIM_NATIVE
    // isoTheme branded colors — used by both Branded (Nim) and Baseline (Swift) variants
    static let current = AppTheme(
        primary: UIColor(red: 0x63/255.0, green: 0x66/255.0, blue: 0xF1/255.0, alpha: 1),     // #6366F1
        background: UIColor(red: 0xF8/255.0, green: 0xFA/255.0, blue: 0xFC/255.0, alpha: 1),   // #F8FAFC
        surface: .white,
        textPrimary: UIColor(red: 0x0F/255.0, green: 0x17/255.0, blue: 0x2A/255.0, alpha: 1),  // #0F172A
        textSecondary: UIColor(red: 0x64/255.0, green: 0x74/255.0, blue: 0x8B/255.0, alpha: 1),// #64748B
        textDisabled: UIColor(red: 0xCB/255.0, green: 0xD5/255.0, blue: 0xE1/255.0, alpha: 1), // #CBD5E1
        error: UIColor(red: 0xEF/255.0, green: 0x44/255.0, blue: 0x44/255.0, alpha: 1),        // #EF4444
        border: UIColor(red: 0xE2/255.0, green: 0xE8/255.0, blue: 0xF0/255.0, alpha: 1),       // #E2E8F0
        inputBackground: UIColor(red: 0xF1/255.0, green: 0xF5/255.0, blue: 0xF9/255.0, alpha: 1) // #F1F5F9
    )
    #else
    // Native: platform system colors
    static let current = AppTheme(
        primary: .systemBlue,
        background: .systemGroupedBackground,
        surface: .systemBackground,
        textPrimary: .label,
        textSecondary: .secondaryLabel,
        textDisabled: .tertiaryLabel,
        error: .systemRed,
        border: .separator,
        inputBackground: .secondarySystemBackground
    )
    #endif
}

// MARK: - Branded Dimensions (isoTheme design tokens)

struct BrandedDimensions {
    static let outerPadding: CGFloat = 16
    static let innerPadding: CGFloat = 12
    static let gap: CGFloat = 8
    static let buttonRadius: CGFloat = 24  // circular (half of addButtonSize)
    static let checkboxRadius: CGFloat = 6
    static let filterPillRadius: CGFloat = 16
    static let titleFontSize: CGFloat = 32
    static let bodyFontSize: CGFloat = 16
    static let captionFontSize: CGFloat = 14
    static let iconFontSize: CGFloat = 24
    static let checkboxSize: CGFloat = 24
    static let addButtonSize: CGFloat = 48
    // Row dimensions (must match Android exactly)
    static let rowHeight: CGFloat = 56
    static let rowPaddingH: CGFloat = 16
    static let rowPaddingV: CGFloat = 12
    static let rowGap: CGFloat = 8
    static let rowRadius: CGFloat = 12
    static let deleteIconSize: CGFloat = 20
}

#if THEME_BRANDED

// Nim-powered branded variant: thin Swift shell + isonim_start()
// The entire UI is driven by the Nim library via CoreGraphics.

// C function exported from Nim — drives the entire branded UI.
@_silgen_name("isonim_start")
func isonim_start(_ rootView: UnsafeMutableRawPointer, _ width: Double, _ height: Double,
                   _ safeTop: Double, _ safeBottom: Double)

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = UIColor(
            red: 0xF8/255.0, green: 0xFA/255.0,
            blue: 0xFC/255.0, alpha: 1)  // isoTheme background

        let vc = UIViewController()
        vc.view = rootView
        window?.rootViewController = vc
        window?.makeKeyAndVisible()

        // Get safe area insets after window is visible
        let safeInsets = window?.safeAreaInsets ?? .zero

        // Hand control to Nim
        let ptr = Unmanaged.passUnretained(rootView).toOpaque()
        let bounds = UIScreen.main.bounds
        isonim_start(ptr, Double(bounds.width), Double(bounds.height),
                     Double(safeInsets.top), Double(safeInsets.bottom))

        return true
    }
}

#elseif THEME_NIM_NATIVE

// Nim-powered native controls variant: thin Swift shell + isonim_native_start()
// The entire UI is driven by Nim using native platform controls (UISwitch, etc.).

@_silgen_name("isonim_native_start")
func isonim_native_start(_ rootView: UnsafeMutableRawPointer, _ width: Double, _ height: Double,
                          _ safeTop: Double, _ safeBottom: Double)

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = UIColor(
            red: 0xF8/255.0, green: 0xFA/255.0,
            blue: 0xFC/255.0, alpha: 1)  // isoTheme background

        let vc = UIViewController()
        vc.view = rootView
        window?.rootViewController = vc
        window?.makeKeyAndVisible()

        // Get safe area insets after window is visible
        let safeInsets = window?.safeAreaInsets ?? .zero

        // Hand control to Nim (native controls variant)
        let ptr = Unmanaged.passUnretained(rootView).toOpaque()
        let bounds = UIScreen.main.bounds
        isonim_native_start(ptr, Double(bounds.width), Double(bounds.height),
                            Double(safeInsets.top), Double(safeInsets.bottom))

        return true
    }
}

#elseif THEME_BASELINE

// Pure Swift baseline variant: isoTheme branded colors with full Swift UI.
// Visually matches the Branded variant but without Nim — serves as a visual reference.

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

#else

// Native variant: pure Swift with platform system colors (UIKit defaults).
// Shows the standard iOS look for comparison.

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

#endif

#if !THEME_BRANDED && !THEME_NIM_NATIVE
// When THEME_BRANDED or THEME_NIM_NATIVE is set, Nim drives the entire UI.
// The Swift task model and view controller below are needed for Baseline and Native variants.

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

    #if THEME_BASELINE
    // Custom checkbox view for branded style (used by Baseline variant)
    private let checkboxView = UIView()
    private let checkmarkLabel = UILabel()
    #endif

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        #if THEME_BASELINE
        // Custom checkbox: 28x28 rounded rect
        checkboxView.translatesAutoresizingMaskIntoConstraints = false
        checkboxView.layer.cornerRadius = BrandedDimensions.checkboxRadius
        checkboxView.layer.borderWidth = 2
        checkboxView.isUserInteractionEnabled = true
        checkboxView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleTapped)))
        contentView.addSubview(checkboxView)

        checkmarkLabel.translatesAutoresizingMaskIntoConstraints = false
        checkmarkLabel.text = "✓"
        checkmarkLabel.font = .systemFont(ofSize: BrandedDimensions.bodyFontSize)
        checkmarkLabel.textColor = .white
        checkmarkLabel.textAlignment = .center
        checkboxView.addSubview(checkmarkLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: BrandedDimensions.bodyFontSize)
        titleLabel.numberOfLines = 0
        contentView.addSubview(titleLabel)

        // Delete button: text "✕" in error color
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.setTitle("✕", for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 18)
        deleteButton.setTitleColor(AppTheme.current.error, for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        contentView.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            checkboxView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: BrandedDimensions.outerPadding),
            checkboxView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkboxView.widthAnchor.constraint(equalToConstant: BrandedDimensions.checkboxSize),
            checkboxView.heightAnchor.constraint(equalToConstant: BrandedDimensions.checkboxSize),

            checkmarkLabel.centerXAnchor.constraint(equalTo: checkboxView.centerXAnchor),
            checkmarkLabel.centerYAnchor.constraint(equalTo: checkboxView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: checkboxView.trailingAnchor, constant: BrandedDimensions.innerPadding),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: BrandedDimensions.innerPadding),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -BrandedDimensions.innerPadding),

            deleteButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: BrandedDimensions.gap),
            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -BrandedDimensions.outerPadding),
            deleteButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: BrandedDimensions.checkboxSize),
            deleteButton.heightAnchor.constraint(equalToConstant: BrandedDimensions.checkboxSize),
        ])
        #else
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
        #endif
    }

    func configure(with task: Task) {
        #if THEME_BASELINE
        titleLabel.text = task.title
        if task.isCompleted {
            checkboxView.backgroundColor = AppTheme.current.primary
            checkboxView.layer.borderColor = AppTheme.current.primary.cgColor
            checkmarkLabel.isHidden = false
            titleLabel.textColor = AppTheme.current.textDisabled
        } else {
            checkboxView.backgroundColor = .clear
            checkboxView.layer.borderColor = AppTheme.current.border.cgColor
            checkmarkLabel.isHidden = true
            titleLabel.textColor = AppTheme.current.textPrimary
        }
        #else
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
        #endif
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
    #if THEME_BASELINE
    // Branded: UIScrollView + stacked UIViews (not UITableView)
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var filterButtons: [UIButton] = []
    #else
    private let tableView = UITableView()
    private let filterControl = UISegmentedControl(items: TaskFilter.allCases.map { $0.title })
    #endif
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
        #if THEME_BASELINE
        // Branded: use explicit font size for title, matching isoTheme 32sp
        navigationController?.navigationBar.prefersLargeTitles = true
        if let appearance = navigationController?.navigationBar.standardAppearance {
            appearance.largeTitleTextAttributes = [
                .foregroundColor: AppTheme.current.textPrimary,
                .font: UIFont.systemFont(ofSize: BrandedDimensions.titleFontSize, weight: .bold)
            ]
            navigationController?.navigationBar.standardAppearance = appearance
            navigationController?.navigationBar.scrollEdgeAppearance = appearance
        }
        #else
        navigationController?.navigationBar.prefersLargeTitles = true
        #endif
        setupInputBar()
        setupTableView()
        setupBottomBar()
        refreshList()
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
        inputField.returnKeyType = .done
        inputField.delegate = self

        #if THEME_BASELINE
        inputField.layer.cornerRadius = BrandedDimensions.buttonRadius
        inputField.font = .systemFont(ofSize: BrandedDimensions.bodyFontSize)
        inputField.textColor = AppTheme.current.textPrimary
        inputField.attributedPlaceholder = NSAttributedString(
            string: "What needs to be done?",
            attributes: [.foregroundColor: AppTheme.current.textSecondary]
        )
        inputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: BrandedDimensions.innerPadding, height: 0))
        inputField.leftViewMode = .always
        inputField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: BrandedDimensions.innerPadding, height: 0))
        inputField.rightViewMode = .always
        #else
        inputField.layer.cornerRadius = 10
        inputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        inputField.leftViewMode = .always
        inputField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        inputField.rightViewMode = .always
        #endif
        container.addSubview(inputField)

        #if THEME_BASELINE
        // Custom add button: 48x48 filled rounded rect with "+" text
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.backgroundColor = AppTheme.current.primary
        addButton.layer.cornerRadius = BrandedDimensions.buttonRadius
        addButton.setTitle("+", for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: BrandedDimensions.iconFontSize)
        addButton.setTitleColor(.white, for: .normal)
        addButton.addTarget(self, action: #selector(addTask), for: .touchUpInside)
        #else
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        addButton.tintColor = AppTheme.current.primary
        addButton.contentVerticalAlignment = .fill
        addButton.contentHorizontalAlignment = .fill
        addButton.addTarget(self, action: #selector(addTask), for: .touchUpInside)
        #endif
        container.addSubview(addButton)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = AppTheme.current.border
        container.addSubview(separator)

        #if THEME_BASELINE
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            inputField.topAnchor.constraint(equalTo: container.topAnchor, constant: BrandedDimensions.gap),
            inputField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: BrandedDimensions.outerPadding),
            inputField.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -BrandedDimensions.gap),
            inputField.heightAnchor.constraint(equalToConstant: BrandedDimensions.addButtonSize),

            addButton.leadingAnchor.constraint(equalTo: inputField.trailingAnchor, constant: BrandedDimensions.gap),
            addButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -BrandedDimensions.outerPadding),
            addButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: BrandedDimensions.addButtonSize),
            addButton.heightAnchor.constraint(equalToConstant: BrandedDimensions.addButtonSize),

            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        #else
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
        #endif

        // Store container reference for table view layout
        container.tag = 100
    }

    // MARK: - Task List View

    private func setupTableView() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No tasks yet.\nTap + to add one."
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0

        guard let inputContainer = view.viewWithTag(100) else { return }

        #if THEME_BASELINE
        // Branded: UIScrollView + stacked UIViews (not UITableView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = AppTheme.current.background
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = BrandedDimensions.rowGap
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        emptyLabel.textColor = AppTheme.current.textSecondary
        emptyLabel.font = .systemFont(ofSize: 18)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: BrandedDimensions.rowGap),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: BrandedDimensions.rowPaddingH),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -BrandedDimensions.rowPaddingH),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -BrandedDimensions.rowGap),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
        #else
        let tableView = self.tableView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = AppTheme.current.background
        tableView.register(TaskCell.self, forCellReuseIdentifier: TaskCell.reuseID)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 60, bottom: 0, right: 0)
        view.addSubview(tableView)

        emptyLabel.textColor = .tertiaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .title3)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])
        #endif
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

        #if THEME_BASELINE
        // Custom filter pills: rounded buttons with 16pt radius
        let filterStack = UIStackView()
        filterStack.translatesAutoresizingMaskIntoConstraints = false
        filterStack.axis = .horizontal
        filterStack.spacing = 4
        filterStack.alignment = .center

        for filter in TaskFilter.allCases {
            let btn = UIButton(type: .system)
            btn.setTitle(filter.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: BrandedDimensions.captionFontSize)
            btn.layer.cornerRadius = BrandedDimensions.filterPillRadius
            btn.clipsToBounds = true
            btn.contentEdgeInsets = UIEdgeInsets(
                top: BrandedDimensions.gap, left: BrandedDimensions.innerPadding,
                bottom: BrandedDimensions.gap, right: BrandedDimensions.innerPadding
            )
            btn.tag = filter.rawValue
            btn.addTarget(self, action: #selector(filterPillTapped(_:)), for: .touchUpInside)
            filterButtons.append(btn)
            filterStack.addArrangedSubview(btn)
        }
        updateFilterPillAppearance()
        bottomContainer.addSubview(filterStack)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setTitle("Clear Completed", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: BrandedDimensions.captionFontSize)
        clearButton.setTitleColor(AppTheme.current.error, for: .normal)
        clearButton.addTarget(self, action: #selector(clearCompleted), for: .touchUpInside)
        bottomContainer.addSubview(clearButton)

        NSLayoutConstraint.activate([
            scrollView.bottomAnchor.constraint(equalTo: bottomContainer.topAnchor),

            bottomContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            topSep.topAnchor.constraint(equalTo: bottomContainer.topAnchor),
            topSep.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            topSep.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            topSep.heightAnchor.constraint(equalToConstant: 0.5),

            filterStack.topAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: BrandedDimensions.innerPadding),
            filterStack.centerXAnchor.constraint(equalTo: bottomContainer.centerXAnchor),

            clearButton.topAnchor.constraint(equalTo: filterStack.bottomAnchor, constant: BrandedDimensions.gap),
            clearButton.centerXAnchor.constraint(equalTo: bottomContainer.centerXAnchor),
            clearButton.bottomAnchor.constraint(equalTo: bottomContainer.bottomAnchor, constant: -BrandedDimensions.gap),
        ])
        #else
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
        #endif
    }

    // MARK: - Actions

    @objc private func addTask() {
        guard let text = inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        tasks.append(Task(title: text))
        inputField.text = ""
        inputField.resignFirstResponder()
        refreshList()
    }

    #if THEME_BASELINE
    @objc private func filterPillTapped(_ sender: UIButton) {
        currentFilter = TaskFilter(rawValue: sender.tag) ?? .all
        updateFilterPillAppearance()
        refreshList()
    }

    private func updateFilterPillAppearance() {
        for btn in filterButtons {
            let isActive = btn.tag == currentFilter.rawValue
            if isActive {
                btn.backgroundColor = AppTheme.current.primary
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = .clear
                btn.setTitleColor(AppTheme.current.textSecondary, for: .normal)
            }
        }
    }

    private func refreshList() {
        // Remove all existing rows
        for arrangedSubview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        // Add a row for each filtered task
        for task in filteredTasks {
            let rowView = createBrandedRow(for: task)
            stackView.addArrangedSubview(rowView)
        }

        updateEmptyState()
    }

    private func createBrandedRow(for task: Task) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.backgroundColor = AppTheme.current.surface
        row.layer.cornerRadius = BrandedDimensions.rowRadius

        // Checkbox
        let checkboxView = UIView()
        checkboxView.translatesAutoresizingMaskIntoConstraints = false
        checkboxView.layer.cornerRadius = BrandedDimensions.checkboxRadius
        checkboxView.layer.borderWidth = 2
        checkboxView.isUserInteractionEnabled = true

        let checkmarkLabel = UILabel()
        checkmarkLabel.translatesAutoresizingMaskIntoConstraints = false
        checkmarkLabel.text = "\u{2713}"
        checkmarkLabel.font = .systemFont(ofSize: BrandedDimensions.bodyFontSize)
        checkmarkLabel.textColor = .white
        checkmarkLabel.textAlignment = .center
        checkboxView.addSubview(checkmarkLabel)

        if task.isCompleted {
            checkboxView.backgroundColor = AppTheme.current.primary
            checkboxView.layer.borderColor = AppTheme.current.primary.cgColor
            checkmarkLabel.isHidden = false
        } else {
            checkboxView.backgroundColor = .clear
            checkboxView.layer.borderColor = AppTheme.current.border.cgColor
            checkmarkLabel.isHidden = true
        }

        let toggleGesture = UITapGestureRecognizer(target: self, action: #selector(rowCheckboxTapped(_:)))
        checkboxView.addGestureRecognizer(toggleGesture)
        row.addSubview(checkboxView)

        // Title label
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = task.title
        titleLabel.font = .systemFont(ofSize: BrandedDimensions.bodyFontSize)
        titleLabel.textColor = task.isCompleted ? AppTheme.current.textDisabled : AppTheme.current.textPrimary
        titleLabel.numberOfLines = 1
        row.addSubview(titleLabel)

        // Delete button
        let deleteButton = UIButton(type: .system)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.setTitle("\u{2715}", for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: BrandedDimensions.deleteIconSize)
        deleteButton.setTitleColor(AppTheme.current.error, for: .normal)
        deleteButton.addTarget(self, action: #selector(rowDeleteTapped(_:)), for: .touchUpInside)
        row.addSubview(deleteButton)

        // Store task ID in tag for identification (use hash)
        let taskIdHash = abs(task.id.hashValue) % Int.max
        checkboxView.tag = taskIdHash
        deleteButton.tag = taskIdHash
        row.tag = taskIdHash

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: BrandedDimensions.rowHeight),

            checkboxView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: BrandedDimensions.rowPaddingH),
            checkboxView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            checkboxView.widthAnchor.constraint(equalToConstant: BrandedDimensions.checkboxSize),
            checkboxView.heightAnchor.constraint(equalToConstant: BrandedDimensions.checkboxSize),

            checkmarkLabel.centerXAnchor.constraint(equalTo: checkboxView.centerXAnchor),
            checkmarkLabel.centerYAnchor.constraint(equalTo: checkboxView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: checkboxView.trailingAnchor, constant: BrandedDimensions.innerPadding),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            deleteButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: BrandedDimensions.gap),
            deleteButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -BrandedDimensions.rowPaddingH),
            deleteButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: BrandedDimensions.checkboxSize),
            deleteButton.heightAnchor.constraint(equalToConstant: BrandedDimensions.checkboxSize),
        ])

        return row
    }

    @objc private func rowCheckboxTapped(_ sender: UITapGestureRecognizer) {
        guard let tag = sender.view?.tag else { return }
        if let idx = tasks.firstIndex(where: { abs($0.id.hashValue) % Int.max == tag }) {
            tasks[idx].isCompleted.toggle()
            refreshList()
        }
    }

    @objc private func rowDeleteTapped(_ sender: UIButton) {
        let tag = sender.tag
        if let idx = tasks.firstIndex(where: { abs($0.id.hashValue) % Int.max == tag }) {
            tasks.remove(at: idx)
            refreshList()
        }
    }

    #else
    @objc private func filterChanged() {
        currentFilter = TaskFilter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        tableView.reloadData()
        updateEmptyState()
    }

    private func refreshList() {
        tableView.reloadData()
        updateEmptyState()
    }
    #endif

    @objc private func clearCompleted() {
        tasks.removeAll { $0.isCompleted }
        refreshList()
    }

    private func updateEmptyState() {
        let empty = filteredTasks.isEmpty
        emptyLabel.isHidden = !empty

        #if THEME_BASELINE
        scrollView.isHidden = empty
        #else
        tableView.isHidden = empty
        #endif

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

#if !THEME_BASELINE
// MARK: - UITableViewDataSource & Delegate (Native variant only; Baseline uses stack view)

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
                self.refreshList()
            }
        }

        cell.onDelete = { [weak self] in
            guard let self = self else { return }
            if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                self.tasks.remove(at: idx)
                self.refreshList()
            }
        }

        return cell
    }
}
#endif

// MARK: - UITextFieldDelegate

extension TaskManagerViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        addTask()
        return true
    }
}

#endif // !THEME_BRANDED && !THEME_NIM_NATIVE
