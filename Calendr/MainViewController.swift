//
//  MainViewController.swift
//  Calendr
//
//  Created by Paker on 26/12/20.
//

import Cocoa
import RxSwift
import RxCocoa

class MainViewController: NSViewController {

    // ViewControllers
    private let popover = NSPopover()
    private let settingsViewController: SettingsViewController

    // Views
    private let statusItem: NSStatusItem
    private let calendarView: CalendarView
    private let titleLabel = Label()
    private let prevBtn = NSButton()
    private let resetBtn = NSButton()
    private let nextBtn = NSButton()
    private let calendarBtn = NSButton()
    private let settingsBtn = NSButton()

    // ViewModels
    private let calendarViewModel: CalendarViewModel
    private let settingsViewModel: SettingsViewModel
    private let statusItemViewModel: StatusItemViewModel
    private let calendarPickerViewModel: CalendarPickerViewModel

    // Reactive
    private let disposeBag = DisposeBag()
    private let dateClick = PublishSubject<Date>()
    private let initialDate = PublishSubject<Date>()
    private let selectedDate = PublishSubject<Date>()

    // Properties
    private let calendarService = CalendarServiceProvider()

    init() {

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        settingsViewModel = SettingsViewModel()

        statusItemViewModel = StatusItemViewModel(
            dateObservable: selectedDate,
            settingsObservable: settingsViewModel.statusItemSettings
        )

        calendarPickerViewModel = CalendarPickerViewModel(calendarService: calendarService)

        settingsViewController = SettingsViewController(
            settingsViewModel: settingsViewModel,
            calendarsViewModel: calendarPickerViewModel
        )

        let hoverSubject = PublishSubject<Date?>()

        // prevent getting 2 events while moving between cells
        let hoverObservable = hoverSubject.debounce(.milliseconds(1), scheduler: MainScheduler.instance)

        calendarViewModel = CalendarViewModel(
            dateObservable: selectedDate,
            hoverObservable: hoverObservable,
            enabledCalendars: calendarPickerViewModel.enabledCalendars,
            calendarService: calendarService
        )

        calendarView = CalendarView(
            viewModel: calendarViewModel,
            hoverObserver: hoverSubject.asObserver(),
            clickObserver: dateClick.asObserver()
        )

        super.init(nibName: nil, bundle: nil)

        setUpBindings()

        setUpPopoverBindings()

        setUpStatusItemBindings()

        calendarService.requestAccess()
    }

    override func loadView() {

        view = NSView()

        let mainView = makeMainView(
            makeHeader(),
            calendarView,
            makeToolBar()
        )

        view.addSubview(mainView)

        mainView.edges(to: view, constant: 8)
    }

    private func makeMainView(_ views: NSView...) -> NSView {

        let mainStackView = NSStackView(.vertical)

        mainStackView.spacing = 4

        mainStackView.addArrangedSubviews(views)

        return mainStackView
    }

    private func makeHeader() -> NSView {

        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)

        [prevBtn, resetBtn, nextBtn].forEach(styleButton)

        prevBtn.image = NSImage(named: NSImage.goBackTemplateName)
        resetBtn.image = NSImage(named: NSImage.refreshTemplateName)
        nextBtn.image = NSImage(named: NSImage.goForwardTemplateName)

        let headerStackView = NSStackView(.horizontal)
        headerStackView.spacing = 0
        headerStackView.addArrangedSubviews(titleLabel, .spacer, prevBtn, resetBtn, nextBtn)

        return headerStackView
    }

    private func makeToolBar() -> NSView {

        [calendarBtn, settingsBtn].forEach(styleButton)

        calendarBtn.image = NSImage(named: NSImage.iconViewTemplateName)?.withSymbolConfiguration(.init(scale: .large))
        settingsBtn.image = NSImage(named: NSImage.actionTemplateName)?.withSymbolConfiguration(.init(scale: .large))

        let toolStackView = NSStackView(.horizontal)
        toolStackView.addArrangedSubviews(.spacer, calendarBtn, settingsBtn)

        return toolStackView
    }

    override func viewDidAppear() {
        view.window?.makeKey()
    }

    private func setUpBindings() {

        makeDateSelector()
            .asObservable()
            .observe(on: MainScheduler.asyncInstance)
            .bind(to: selectedDate)
            .disposed(by: disposeBag)

        Observable.merge(
            NotificationCenter.default.rx.notification(.NSCalendarDayChanged, object: nil).toVoid(),
            rx.sentMessage(#selector(NSViewController.viewDidDisappear)).toVoid()
        )
        .startWith(())
        .map { Date() }
        .bind(to: initialDate)
        .disposed(by: disposeBag)

        dateClick
            .bind(to: selectedDate)
            .disposed(by: disposeBag)

        selectedDate
            .map(DateFormatter(format: "MMM yyyy").string(from:))
            .bind(to: titleLabel.rx.text)
            .disposed(by: disposeBag)

        calendarBtn.rx.tap.bind {
            if let appUrl = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "webcal://")!) {
                NSWorkspace.shared.open(appUrl)
            }
        }
        .disposed(by: disposeBag)

        settingsBtn.rx.tap.bind { [weak self, settingsViewController] in
            self?.presentAsModalWindow(settingsViewController)
        }
        .disposed(by: disposeBag)
    }

    private func setUpStatusItemBindings() {
        guard
            let statusBarButton = statusItem.button,
            let statusItemView = statusBarButton.cell?.controlView
        else { return }

        // fix a bug with trackpad click
        statusBarButton.sendAction(on: .leftMouseDown)

        statusBarButton.rx.tap.bind { [popover] in
            popover.show(relativeTo: .zero, of: statusItemView, preferredEdge: .maxY)
        }
        .disposed(by: disposeBag)

        popover.rx.observe(\.isShown)
            .bind(to: statusBarButton.rx.isHighlighted)
            .disposed(by: disposeBag)

        statusItemViewModel.width
            .bind(to: statusItem.rx.length)
            .disposed(by: disposeBag)

        statusItemViewModel.text
            .bind(to: statusBarButton.rx.attributedTitle)
            .disposed(by: disposeBag)
    }

    private func setUpPopoverBindings() {

        popover.contentViewController = self

        popover.rx.observe(\.isShown)
            .observe(on: MainScheduler.asyncInstance)
            .bind(to: popover.rx.animates)
            .disposed(by: disposeBag)

        settingsViewController.rx.sentMessage(#selector(NSViewController.viewWillAppear))
            .toVoid()
            .map { NSPopover.Behavior.applicationDefined }
            .bind(to: popover.rx.behavior)
            .disposed(by: disposeBag)

        settingsViewController.rx.sentMessage(#selector(NSViewController.viewDidDisappear))
            .toVoid()
            .startWith(())
            .map { NSPopover.Behavior.transient }
            .bind(to: popover.rx.behavior)
            .disposed(by: disposeBag)
    }

    private func styleButton(_ button: NSButton) {
        button.size(equalTo: 22)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.refusesFirstResponder = true
    }

    private func makeDateSelector() -> DateSelector {

        let keySubject = PublishSubject<UInt16>()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event -> NSEvent? in
            if 123...126 ~= event.keyCode {
                keySubject.onNext(event.keyCode)
                return nil
            }
            return event
        }

        let keyLeft = keySubject.matching(123).toVoid()
        let keyRight = keySubject.matching(124).toVoid()
        let keyDown = keySubject.matching(125).toVoid()
        let keyUp = keySubject.matching(126).toVoid()


        let dateSelector = DateSelector(
            initial: initialDate,
            selected: selectedDate,
            reset: resetBtn.rx.tap.asObservable(),
            prevDay: keyLeft,
            nextDay: keyRight,
            prevWeek: keyUp,
            nextWeek: keyDown,
            prevMonth: prevBtn.rx.tap.asObservable(),
            nextMonth: nextBtn.rx.tap.asObservable()
        )

        return dateSelector
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension NSStatusBarButton {
    open override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // keep highlighted
        highlight(true)
    }
}
