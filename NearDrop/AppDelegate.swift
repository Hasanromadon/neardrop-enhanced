//
//  AppDelegate.swift
//  NearDrop
//
//  Created by Grishka on 08.04.2023.
//

import Cocoa
import UserNotifications
import NearbyShare

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, MainAppDelegate{
	private var statusItem:NSStatusItem?
	private var mainWindow:NSWindow?
	private var visibilityButton:NSButton?
	private var statusLabel:NSTextField?
	private var activityTextView:NSTextView?
	private var isVisible=true
	private var activeIncomingTransfers:[String:TransferInfo]=[:]
	private var recentTransfers:[TransferHistoryItem]=[]

    func applicationDidFinishLaunching(_ aNotification: Notification) {
		isVisible=UserDefaults.standard.object(forKey: "NearDropVisible") as? Bool ?? true
		statusItem=NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		statusItem?.button?.image=NSImage(named: "MenuBarIcon")
		statusItem?.button?.target=self
		statusItem?.button?.action=#selector(showMainWindow(_:))
		statusItem?.behavior = .removalAllowed
		NSApplication.shared.setActivationPolicy(.regular)
		createMainWindow()
		
		let nc=UNUserNotificationCenter.current()
		nc.requestAuthorization(options: [.alert, .sound]) { granted, err in
			if !granted{
				DispatchQueue.main.async {
					self.showNotificationsDeniedAlert()
				}
			}
		}
		nc.delegate=self
		let incomingTransfersCategory=UNNotificationCategory(identifier: "INCOMING_TRANSFERS", actions: [
			UNNotificationAction(identifier: "ACCEPT", title: NSLocalizedString("Accept", comment: ""), options: UNNotificationActionOptions.authenticationRequired),
			UNNotificationAction(identifier: "DECLINE", title: NSLocalizedString("Decline", comment: ""))
		], intentIdentifiers: [])
		let errorsCategory=UNNotificationCategory(identifier: "ERRORS", actions: [], intentIdentifiers: [])
		nc.setNotificationCategories([incomingTransfersCategory, errorsCategory])
		NearbyConnectionManager.shared.mainAppDelegate=self
		NearbyConnectionManager.shared.setVisibility(isVisible)
		showMainWindow(nil)
	}
	
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		statusItem?.isVisible=true
		showMainWindow(nil)
		return true
	}

	private func createMainWindow(){
		let window=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 460), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
		window.title="NearDrop"
		window.isReleasedWhenClosed=false
		window.center()
		window.contentView=NSView()

		let title=NSTextField(labelWithString: NSLocalizedString("NearDropWindowTitle", value: "Share files with nearby Android devices", comment: ""))
		title.font=NSFont.systemFont(ofSize: 20, weight: .semibold)
		title.lineBreakMode = .byWordWrapping
		title.maximumNumberOfLines=2
		let status=NSTextField(labelWithString: "")
		statusLabel=status
		let device=NSTextField(labelWithString: String(format: NSLocalizedString("DeviceName", value: "Device name: %@", comment: ""), arguments: [Host.current().localizedName ?? "Mac"]))
		let visibility=NSButton(checkboxWithTitle: NSLocalizedString("VisibleCheckbox", value: "Allow devices on this Wi-Fi to discover this Mac", comment: ""), target: self, action: #selector(toggleVisibilityFromWindow))
		visibility.state = isVisible ? .on : .off
		visibilityButton=visibility
		let downloads=NSButton(title: NSLocalizedString("OpenDownloads", value: "Open Downloads", comment: ""), target: self, action: #selector(openDownloads))
		downloads.bezelStyle = .rounded
		let activityTitle=NSTextField(labelWithString: NSLocalizedString("RecentTransfers", value: "Recent incoming transfers", comment: ""))
		activityTitle.font=NSFont.systemFont(ofSize: 14, weight: .semibold)
		let activityView=NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 140))
		activityView.isEditable=false
		activityView.isSelectable=true
		activityView.drawsBackground=false
		activityView.textContainerInset=NSSize(width: 6, height: 6)
		activityTextView=activityView
		let activityScrollView=NSScrollView()
		activityScrollView.hasVerticalScroller=true
		activityScrollView.borderType = .bezelBorder
		activityScrollView.documentView=activityView
		activityScrollView.translatesAutoresizingMaskIntoConstraints=false
		NSLayoutConstraint.activate([
			activityScrollView.widthAnchor.constraint(equalToConstant: 432),
			activityScrollView.heightAnchor.constraint(equalToConstant: 140)
		])

		let stack=NSStackView(views: [title, status, device, visibility, downloads, activityTitle, activityScrollView])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing=14
		stack.translatesAutoresizingMaskIntoConstraints=false
		window.contentView?.addSubview(stack)
		if let content=window.contentView{
			NSLayoutConstraint.activate([
				stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
				stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
				stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
			])
		}
		mainWindow=window
		updateVisibilityUI()
		updateActivityHistory()
	}

	@objc private func showMainWindow(_ sender: Any?){
		if mainWindow == nil { createMainWindow() }
		NSApplication.shared.activate(ignoringOtherApps: true)
		mainWindow?.makeKeyAndOrderFront(sender)
	}

	@objc private func toggleVisibilityFromWindow(_ sender: NSButton){
		setVisibility(sender.state == .on)
	}

	private func setVisibility(_ visible: Bool){
		isVisible=visible
		UserDefaults.standard.set(visible, forKey: "NearDropVisible")
		NearbyConnectionManager.shared.setVisibility(visible)
		updateVisibilityUI()
	}

	private func updateVisibilityUI(){
		visibilityButton?.state = isVisible ? .on : .off
		statusLabel?.stringValue = isVisible
			? NSLocalizedString("VisibilityEnabled", value: "NearDrop is available on your local Wi-Fi.", comment: "")
			: NSLocalizedString("VisibilityDisabled", value: "NearDrop is hidden and will not accept new connections.", comment: "")
	}

	@objc private func openDownloads(_ sender: Any?){
		let downloads=FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
		NSWorkspace.shared.open(downloads)
	}

    func applicationWillTerminate(_ aNotification: Notification) {
		UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
	
	func showNotificationsDeniedAlert(){
		let alert=NSAlert()
		alert.alertStyle = .critical
		alert.messageText=NSLocalizedString("NotificationsDenied.Title", value: "Notification Permission Required", comment: "")
		alert.informativeText=NSLocalizedString("NotificationsDenied.Message", value: "NearDrop needs to be able to display notifications for incoming file transfers. Please allow notifications in System Settings.", comment: "")
		alert.addButton(withTitle: NSLocalizedString("NotificationsDenied.OpenSettings", value: "Open settings", comment: ""))
		alert.addButton(withTitle: NSLocalizedString("Quit", value: "Quit NearDrop", comment: ""))
		let result=alert.runModal()
		if result==NSApplication.ModalResponse.alertFirstButtonReturn{
			NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
		}else if result==NSApplication.ModalResponse.alertSecondButtonReturn{
			NSApplication.shared.terminate(nil)
		}
	}
	
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		guard let transferID=response.notification.request.content.userInfo["transferID"] as? String else{
			completionHandler()
			return
		}
		switch response.actionIdentifier{
		case "ACCEPT":
			NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: true)
			updateTransferHistory(id: transferID, status: NSLocalizedString("TransferAccepted", value: "Accepted", comment: ""))
		case "DECLINE":
			NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: false)
			updateTransferHistory(id: transferID, status: NSLocalizedString("TransferDeclined", value: "Declined", comment: ""))
			activeIncomingTransfers.removeValue(forKey: transferID)
		default:
			showTransferConsent(transferID: transferID)
		}
		completionHandler()
	}
	
	func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {
		let fileStr:String
		if let textTitle=transfer.textDescription{
			fileStr=textTitle
		}else if transfer.files.count==1{
			fileStr=transfer.files[0].name
		}else{
			fileStr=String.localizedStringWithFormat(NSLocalizedString("NFiles", value: "%d files", comment: ""), transfer.files.count)
		}
		let notificationContent=UNMutableNotificationContent()
		notificationContent.title="NearDrop"
		notificationContent.subtitle=String(format:NSLocalizedString("PinCode", value: "PIN: %@", comment: ""), arguments: [transfer.pinCode!])
		notificationContent.body=String(format: NSLocalizedString("DeviceSendingFiles", value: "%1$@ is sending you %2$@", comment: ""), arguments: [device.name, fileStr])
		notificationContent.sound = .default
		notificationContent.categoryIdentifier="INCOMING_TRANSFERS"
		notificationContent.userInfo=["transferID": transfer.id]
		let notificationReq=UNNotificationRequest(identifier: "transfer_"+transfer.id, content: notificationContent, trigger: nil)
		UNUserNotificationCenter.current().add(notificationReq)
		self.activeIncomingTransfers[transfer.id]=TransferInfo(device: device, transfer: transfer)
		DispatchQueue.main.async {
			let item=TransferHistoryItem(id: transfer.id, date: Date(), deviceName: device.name, fileDescription: fileStr, status: NSLocalizedString("TransferWaiting", value: "Waiting for approval", comment: ""))
			self.recentTransfers.removeAll(where: {$0.id == transfer.id})
			self.recentTransfers.insert(item, at: 0)
			if self.recentTransfers.count>20 { self.recentTransfers=Array(self.recentTransfers.prefix(20)) }
			self.updateActivityHistory()
		}
	}
	
	func incomingTransfer(id: String, didFinishWith error: Error?) {
		guard let transfer=self.activeIncomingTransfers[id] else {return}
		if let error=error{
			let notificationContent=UNMutableNotificationContent()
			notificationContent.title=String(format: NSLocalizedString("TransferError", value: "Failed to receive files from %@", comment: ""), arguments: [transfer.device.name])
			if let ne=(error as? NearbyError){
				switch ne{
				case .inputOutput:
					notificationContent.body="I/O Error";
				case .protocolError(_):
					notificationContent.body=NSLocalizedString("Error.Protocol", value: "Communication error", comment: "")
				case .requiredFieldMissing:
					notificationContent.body=NSLocalizedString("Error.Protocol", value: "Communication error", comment: "")
				case .ukey2:
					notificationContent.body=NSLocalizedString("Error.Crypto", value: "Encryption error", comment: "")
				case .canceled(reason: _):
					break; // can't happen for incoming transfers
				}
			}else{
				notificationContent.body=error.localizedDescription
			}
			notificationContent.categoryIdentifier="ERRORS"
			UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "transferError_"+id, content: notificationContent, trigger: nil))
			updateTransferHistory(id: id, status: NSLocalizedString("TransferFailed", value: "Failed", comment: ""))
		}else{
			updateTransferHistory(id: id, status: NSLocalizedString("TransferCompleted", value: "Received", comment: ""))
		}
		UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_"+id])
		self.activeIncomingTransfers.removeValue(forKey: id)
	}

	private func updateTransferHistory(id: String, status: String){
		guard Thread.isMainThread else{
			DispatchQueue.main.async { self.updateTransferHistory(id: id, status: status) }
			return
		}
		guard let index=recentTransfers.firstIndex(where: {$0.id == id}) else {return}
		recentTransfers[index].status=status
		updateActivityHistory()
	}

	private func updateActivityHistory(){
		guard Thread.isMainThread else{
			DispatchQueue.main.async { self.updateActivityHistory() }
			return
		}
		guard let activityTextView else {return}
		let formatter=DateFormatter()
		formatter.timeStyle = .short
		formatter.dateStyle = .none
		activityTextView.string=recentTransfers.isEmpty
			? NSLocalizedString("NoRecentTransfers", value: "No incoming transfers yet.", comment: "")
			: recentTransfers.map { "\(formatter.string(from: $0.date))  •  \($0.deviceName)  •  \($0.fileDescription)  —  \($0.status)" }.joined(separator: "\n")
	}

	private func showTransferConsent(transferID: String){
		DispatchQueue.main.async {
			guard let pending=self.activeIncomingTransfers[transferID] else{return}
			self.showMainWindow(nil)
			let files=pending.transfer.textDescription ?? pending.transfer.files.map(\.name).joined(separator: ", ")
			let alert=NSAlert()
			alert.alertStyle = .warning
			alert.messageText=String(format: NSLocalizedString("ConsentPromptTitle", value: "%@ wants to send files", comment: ""), pending.device.name)
			alert.informativeText=String(format: NSLocalizedString("ConsentPromptMessage", value: "%@\nPIN: %@", comment: ""), files, pending.transfer.pinCode ?? "—")
			alert.addButton(withTitle: NSLocalizedString("Accept", value: "Accept", comment: ""))
			alert.addButton(withTitle: NSLocalizedString("Decline", value: "Decline", comment: ""))
			let accepted=alert.runModal() == .alertFirstButtonReturn
			NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: accepted)
			self.updateTransferHistory(id: transferID, status: accepted
				? NSLocalizedString("TransferAccepted", value: "Accepted", comment: "")
				: NSLocalizedString("TransferDeclined", value: "Declined", comment: ""))
			if !accepted { self.activeIncomingTransfers.removeValue(forKey: transferID) }
		}
	}
}

struct TransferInfo{
	let device:RemoteDeviceInfo
	let transfer:TransferMetadata
}

struct TransferHistoryItem{
	let id:String
	let date:Date
	let deviceName:String
	let fileDescription:String
	var status:String
}
