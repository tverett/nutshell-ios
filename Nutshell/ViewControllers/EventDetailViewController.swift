/*
* Copyright (c) 2015, Tidepool Project
*
* This program is free software; you can redistribute it and/or modify it under
* the terms of the associated License, which is identical to the BSD 2-Clause
* License as published by the Open Source Initiative at opensource.org.
*
* This program is distributed in the hope that it will be useful, but WITHOUT
* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
* FOR A PARTICULAR PURPOSE. See the License for more details.
*
* You should have received a copy of the License along with this program; if
* not, you can obtain one from Tidepool Project at tidepool.org.
*/


import UIKit
import CoreData

class EventDetailViewController: BaseUIViewController, GraphContainerViewDelegate, UIGestureRecognizerDelegate, EventPhotoCollectViewDelegate {
    
    var eventItem: NutEventItem?
    var eventGroup: NutEvent?
    private var originalId: String?
    private var switchedEvents: Bool = false
    private var isWorkout: Bool = false
    
    @IBOutlet weak var graphSectionView: UIView!
    @IBOutlet weak var graphLayerContainer: UIView!
    @IBOutlet weak var missingDataAdvisoryView: UIView!
    @IBOutlet weak var missingDataAdvisoryTitle: NutshellUILabel!
    @IBOutlet weak var eatAgainView: UIView!
    private var graphContainerView: TidepoolGraphView?
    
    @IBOutlet weak var headerOverlayContainer: UIControl!
    @IBOutlet weak var topSectionContainer: EventPhotoCollectView!
    var titleLabel: UILabel?
    var notesLabel: UILabel?
    var dateLabel: UILabel?
    var locationLabel: UILabel?
    var locationIcon: UIImageView?
    
    @IBOutlet weak var nutCrackedButton: NutshellUIButton!
    @IBOutlet weak var nutCrackedLabel: NutshellUILabel!
    
    @IBOutlet weak var photoDisplayImageView: UIImageView!
    
    private var eventTime = NSDate()
    private var placeholderLocationString = "Note location here!"

    //
    // MARK: - Base methods
    //

    override func viewDidLoad() {
        super.viewDidLoad()
        // remember original nut item we viewed, for return
        originalId = eventItem?.nutEventIdString()
        configureDetailView()
        // We use a custom back button so we can redirect back when the event has changed. This tweaks the arrow positioning to match the iOS back arrow position
        self.navigationItem.leftBarButtonItem?.imageInsets = UIEdgeInsetsMake(0.0, -8.0, -1.0, 0.0)
        topSectionContainer.backgroundColor = Styles.darkPurpleColor
        let notificationCenter = NSNotificationCenter.defaultCenter()
        notificationCenter.addObserver(self, selector: #selector(EventDetailViewController.graphDataChanged(_:)), name: NewBlockRangeLoadedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(EventDetailViewController.reachabilityChanged(_:)), name: ReachabilityChangedNotification, object: nil)
        configureForReachability()
    }
 
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    func reachabilityChanged(note: NSNotification) {
        configureForReachability()
    }
    
    private func configureForReachability() {
        let connected = APIConnector.connector().isConnectedToNetwork()
        missingDataAdvisoryTitle.text = connected ? "There is no data in here!" : "You are currently offline!"
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    private var viewIsForeground: Bool = false
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        //NSLog("EventDetailVC: viewWillAppear")
        APIConnector.connector().trackMetric("Viewed Data Screen")
        
        if eventItem == nil {
            NSLog("Error: No Event at EventDetailVC viewWillAppear!")
            self.performSegueWithIdentifier("unwindSegueToHome", sender: self)
            return
        }

        viewIsForeground = true
        layoutHeaderView()
        checkUpdateGraph()
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        viewIsForeground = false
    }

    //
    // MARK: - Navigation
    //
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        super.prepareForSegue(segue, sender: sender)
        if segue.identifier == EventViewStoryboard.SegueIdentifiers.EventItemEditSegue {
            // "Edit" case
            let eventEditVC = segue.destinationViewController as! EventAddOrEditViewController
            eventEditVC.eventItem = eventItem
            eventEditVC.eventGroup = eventGroup
            APIConnector.connector().trackMetric("Clicked Edit (Data Screen)")
        } else if segue.identifier == EventViewStoryboard.SegueIdentifiers.EventItemAddSegue {
            // "Eat again" case...
            let eventAddVC = segue.destinationViewController as! EventAddOrEditViewController
            // no existing item to pass along...
            eventAddVC.eventGroup = eventGroup
            APIConnector.connector().trackMetric("Clicked Eat Again (Data Screen)")
        } else {
            NSLog("Other segue from eventDetail \(segue.identifier)")
        }
    }
    
    @IBAction func done(segue: UIStoryboardSegue) {
        NSLog("unwind segue to eventDetail done")
        if let eventAddOrEditVC = segue.sourceViewController as? EventAddOrEditViewController {
            // update group and item!
            self.eventGroup = eventAddOrEditVC.eventGroup
            self.eventItem = eventAddOrEditVC.eventItem
            if eventAddOrEditVC.eventItem != nil {
                // The event may have changed, so reload everything.
                configureDetailView() // setup done at viewDidLoad time dependent upon the event
                configureGraphContainer()
                configurePhotoBackground()
            } else {
                NSLog("EventDetailVC detected deleted event at done!")
                // Note: will segue out at ViewWillDisplay...
            }
        } else if let _ = segue.sourceViewController as? ShowPhotoViewController {
            APIConnector.connector().trackMetric("Clicked Back to Data Screen (Photo Screen)")
//            let newPhotoIndex = photoViewVC.imageIndex
//            if newPhotoIndex > 0 {
//                // Set image 0 as the last one viewed in the photo viewer...
//                if let mealItem = eventItem as? NutMeal {
//                    shiftPhotoArrayLeft(mealItem)
//                    if newPhotoIndex > 1 {
//                        shiftPhotoArrayLeft(mealItem)
//                    }
//                    // Save changes to database
//                    mealItem.saveChanges()
//                    configurePhotoBackground()
//                }
//            }
        }
     }

    private func shiftPhotoArrayLeft(mealItem: NutMeal) {
        // shift photo urls - either 2 or 3...
        let photoUrls = mealItem.photoUrlArray()
        if photoUrls.count > 1 {
            mealItem.photo = photoUrls[1]
            if photoUrls.count == 3 {
                mealItem.photo2 = photoUrls[2]
                mealItem.photo3 = photoUrls[0]
            } else {
                mealItem.photo2 = photoUrls[0]
                mealItem.photo3 = ""
            }
        }
    }
    
    /// Works with graphDataChanged to ensure graph is up-to-date after notification of database changes whether this VC is in the foreground or background.
    private func checkUpdateGraph() {
        if graphNeedsUpdate {
            graphNeedsUpdate = false
            if let graphContainerView = graphContainerView {
                graphContainerView.loadGraphData()
            }
        }
    }
    
    private var graphNeedsUpdate: Bool  = false
    func graphDataChanged(note: NSNotification) {
        graphNeedsUpdate = true
        if viewIsForeground {
            //NSLog("EventDetailView: graphDataChanged, reloading")
            checkUpdateGraph()
        } else {
            NSLog("EventDetailView: graphDataChanged, in background")
        }
    }

    @IBAction func cancel(segue: UIStoryboardSegue) {
        NSLog("unwind segue to eventDetail cancel")
    }

    //
    // MARK: - Button handlers
    //

    @IBAction func backButtonHandler(sender: AnyObject) {
        APIConnector.connector().trackMetric("Clicked Back (Data Screen)")
        if self.eventItem?.nutEventIdString() == originalId && !switchedEvents {
            self.performSegueWithIdentifier("unwindSegueToDone", sender: self)
        } else {
            // We have a new NutEvent, won't want to return to group event scene...
            self.performSegueWithIdentifier("unwindSegueToHome", sender: self)
        }
    }
    
    private func configureNutCracked() {
        if let eventItem = eventItem {
            nutCrackedLabel.text = eventItem.nutCracked ? NSLocalizedString("successButtonTitle", comment:"Success!") : NSLocalizedString("nutCrackedButtonTitle", comment:"Success?")
            nutCrackedButton.selected = eventItem.nutCracked
        }
    }
    
    @IBAction func nutCrackedButtonHandler(sender: AnyObject) {
        nutCrackedButton.selected = !nutCrackedButton.selected

        if let eventItem = eventItem {
            if nutCrackedButton.selected {
                APIConnector.connector().trackMetric("Clicked to Crack the Nut")
            } else {
                APIConnector.connector().trackMetric("Clicked to Uncrack the Nut")
            }
            eventItem.nutCracked = nutCrackedButton.selected
            // Save changes to database
            eventItem.saveChanges()
            configureNutCracked()
        }
    }
    
    func didSelectItemAtIndexPath(indexPath: NSIndexPath) {
        self.photoOverlayTouchHandler(self)
    }
    
    @IBAction func photoOverlayTouchHandler(sender: AnyObject) {
        if let graphContainerView = graphContainerView {
            graphContainerView.centerGraphOnEvent(animated: true)
            APIConnector.connector().trackMetric("Clicked Header to Re-Center Data (Data Screen)")
        }
    }
    
    @IBAction func photoDisplayButtonHandler(sender: AnyObject) {
        if let mealItem = eventItem as? NutMeal {
            let photoUrls = mealItem.photoUrlArray()
            if photoUrls.count > 0 {
                let firstPhotoUrl = mealItem.firstPictureUrl()
                if !firstPhotoUrl.isEmpty {
                    let storyboard = UIStoryboard(name: "EventView", bundle: nil)
                    let photoVC = storyboard.instantiateViewControllerWithIdentifier("ShowPhotoViewController") as! ShowPhotoViewController
                    photoVC.editAllowed = false
                    photoVC.mealTitle = mealItem.title
                    photoVC.photoURLs = mealItem.photoUrlArray()
                    photoVC.imageIndex = 0
                    self.navigationController?.pushViewController(photoVC, animated: true)
                    APIConnector.connector().trackMetric("Clicked Photos (Data Screen)")
                }
            }
        }
    }
    
//    @IBAction func zoomInButtonHandler(sender: AnyObject) {
//        if let graphContainerView = graphContainerView {
//            graphContainerView.zoomInOut(true)
//            adjustZoomButtons()
//        }
//    }
//    
//    @IBAction func zoomOutButtonHandler(sender: AnyObject) {
//        if let graphContainerView = graphContainerView {
//            graphContainerView.zoomInOut(false)
//            adjustZoomButtons()
//        }
//    }
//    
//    @IBOutlet weak var zoomInButton: UIButton!
//    @IBOutlet weak var zoomOutButton: UIButton!
//    private func adjustZoomButtons() {
//        if let graphContainerView = graphContainerView {
//            zoomInButton.enabled = graphContainerView.canZoomIn()
//            zoomOutButton.enabled = graphContainerView.canZoomOut()
//        }
//    }
    
    //
    // MARK: - Configuration
    //
    
    private var curPhotoDisplayedIndex = 0
    private func configurePhotoBackground() {
        if let eventItem = eventItem {
            //NSLog("EventDetailVC: configurePhotoBackground")
            photoDisplayImageView.hidden = true
            let photoUrls = eventItem.photoUrlArray()
            topSectionContainer.setNeedsLayout()
            topSectionContainer.layoutIfNeeded()
            topSectionContainer.photoURLs = photoUrls
            topSectionContainer.photoDisplayMode = .ScaleAspectFill
            topSectionContainer.delegate = self // handle touches here!
            topSectionContainer.configurePhotoCollection()
            if photoUrls.count > 0 {
                photoDisplayImageView.hidden = false
                photoDisplayImageView.image = photoUrls.count == 1 ? UIImage(named: "singlePhotoIcon") : UIImage(named: "multiPhotoIcon")
            }
        }
    }
    
    private func configureDetailView() {
        //NSLog("EventDetailVC: configureDetailView")
        if let eventItem = eventItem {
            configureNutCracked()

            if let _ = eventItem as? NutWorkout {
                isWorkout = true
                eatAgainView.hidden = true
            }
            
            titleLabel = addLabel(eventItem.title, labelStyle: "detailHeaderTitle", currentView: titleLabel)
            notesLabel = addLabel(eventItem.notes, labelStyle: "detailHeaderNotes", currentView: notesLabel)
            notesLabel!.hidden = eventItem.notes.isEmpty

            eventTime = eventItem.time
            NutUtils.setFormatterTimezone(eventItem.tzOffsetSecs)
            let dateLabelText = NutUtils.standardUIDateString(eventTime)
            dateLabel = addLabel(dateLabelText, labelStyle: "detailHeaderDate", currentView: dateLabel)

            locationLabel = addLabel(eventItem.location, labelStyle: "detailHeaderLocation", currentView: locationLabel)
            locationLabel!.hidden = eventItem.location.isEmpty
            if locationIcon != nil {
                locationIcon!.removeFromSuperview()
                locationIcon = nil
            }
            if !eventItem.location.isEmpty {
                let icon = UIImage(named:"placeSmallIcon")
                locationIcon = UIImageView(image: icon)
                headerOverlayContainer.addSubview(locationIcon!)
            }
        }
    }

    private func addLabel(labelText: String, labelStyle: String, currentView: UILabel?) -> UILabel {
        
        let paragraphStyle = NSParagraphStyle.defaultParagraphStyle().mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.alignment = .Center
        paragraphStyle.lineBreakMode = .ByWordWrapping
        paragraphStyle.lineHeightMultiple = 0.9
        
        let label = NutshellUILabel(frame: CGRectZero)
        label.usage = labelStyle
        label.numberOfLines = 0
        label.attributedText = NSMutableAttributedString(string: labelText, attributes: [NSFontAttributeName: label.font, NSForegroundColorAttributeName: label.textColor, NSParagraphStyleAttributeName:paragraphStyle])
        if let currentView = currentView {
            currentView.removeFromSuperview()
        }
        headerOverlayContainer.addSubview(label)
        return label
    }

    //
    // MARK: - Layout Header
    //

    private let kMinTopMargin: CGFloat = 5.0
    private let kTargetTopMargin: CGFloat = 20.0
    private let kMinBottomMargin: CGFloat = 5.0
    private let kTargetBottomMargin: CGFloat = 20.0
    private let kMinTitleSubtitleSeparation: CGFloat = 2.0
    private let kTargetTitleSubtitleSeparation: CGFloat = 10.0
    private let kMinSubtitleDateSeparation: CGFloat = 2.0
    private let kTargetSubtitleDateSeparation: CGFloat = 10.0
    private let kMinDateLocationSeparation: CGFloat = 2.0
    private let kTargetDateLocationSeparation: CGFloat = 10.0
    private let klocationIconOffset: CGFloat = 8.0
    
    private func sizeNeededForLabel(availWidth: CGFloat, availHeight: CGFloat, label: UILabel?) -> CGSize {
        if let attribStr = label?.attributedText {
            let sizeNeeded = attribStr.boundingRectWithSize(CGSize(width: availWidth, height: availHeight), options: NSStringDrawingOptions.UsesLineFragmentOrigin, context: nil)
            return CGSize(width: ceil(sizeNeeded.width), height: ceil(sizeNeeded.height))
        } else {
            return CGSizeZero
        }
    }
    
    private func centerLabelInTopFrame(label: UILabel?, frame: CGRect) -> CGSize {
        var calcFrame = CGRectZero
        if let label = label {
            let sizeNeeded = sizeNeededForLabel(frame.size.width, availHeight: frame.size.height, label: label)
            calcFrame = frame
            calcFrame.size.height = ceil(sizeNeeded.height)
            calcFrame.origin.x += ceil((frame.size.width - sizeNeeded.width)/2)
            calcFrame.origin.y = ceil(calcFrame.origin.y)
            calcFrame.size.width = ceil(sizeNeeded.width)
            label.frame = calcFrame
            return sizeNeeded
        } else {
            return CGSizeZero
        }
    }
    
    private func growHeaderOverlayContainer(newMultiplier: CGFloat) -> CGRect {
        for c in topSectionContainer.constraints {
            // remove current constraint because multiplier can't be set
            if c.firstAttribute == NSLayoutAttribute.Width {
                topSectionContainer.removeConstraint(c)
                break
            }
        }
        let newC = NSLayoutConstraint(item: topSectionContainer, attribute: NSLayoutAttribute.Width, relatedBy: NSLayoutRelation.Equal, toItem: topSectionContainer, attribute: NSLayoutAttribute.Height, multiplier: newMultiplier, constant: 0.0)
        topSectionContainer.addConstraint(newC)
        topSectionContainer.setNeedsLayout()
        topSectionContainer.layoutIfNeeded()
        headerOverlayContainer.setNeedsLayout()
        headerOverlayContainer.layoutIfNeeded()
        return headerOverlayContainer.bounds
    }
    
    private func shrinkLabelHeight(curAllocation: CGFloat, minAllocation: CGFloat, width: CGFloat, label: UILabel) -> CGFloat {
        // trim label height allocation to minAllocation, returning reclaimed delta
        if curAllocation > minAllocation {
            let newAllocation = sizeNeededForLabel(width, availHeight: minAllocation, label: label).height
            let reclaimable = curAllocation - newAllocation
            if reclaimable > 0 {
                return reclaimable
            }
        }
        return 0.0
    }

/*
    Top section size should be minimum of half the screen width (for 2:1 aspect ratio), up to perhaps a 4:3 aspect ratio (to leave enough room for the graph at the bottom after subtracting space for the top and middle bars).
    
    Measure what is needed for all fields; date field is one line, the others can be multiple lines. If that fits with some space to distribute between fields, we're pretty much done.
    
    If not, start by growing the section size, trying aspect ratios of 3:2 and then 4:3. If we still don't have enough room for all fields, start limiting those fields to some % of the space, first location, then title, then notes.
    
    Distribute the remaining space proportionally between the fields, with slightly more space at top and bottom margins.
*/

    private func layoutHeaderView() {
        
        //NSLog("EventDetailVC: layoutHeaderView")
        headerOverlayContainer.setNeedsLayout()
        headerOverlayContainer.layoutIfNeeded()
        // start with header aspect ratio of 2:1
        var containerframe = growHeaderOverlayContainer(2.0)
        
        let titleHeightNeeded = sizeNeededForLabel(containerframe.width, availHeight: containerframe.height, label: titleLabel).height
        let dateHeightNeeded = sizeNeededForLabel(containerframe.width, availHeight: containerframe.height, label: dateLabel).height
        // note subtitle and location are optional
        let subtitleHeightNeeded = notesLabel!.hidden ? 0.0 : sizeNeededForLabel(containerframe.width, availHeight: containerframe.height, label: notesLabel).height
        let locationHeightNeeded = locationLabel!.hidden ? 0.0 : sizeNeededForLabel(containerframe.width, availHeight: containerframe.height, label: locationLabel).height
        var totalHeightNeeded = titleHeightNeeded + subtitleHeightNeeded + dateHeightNeeded + locationHeightNeeded
        let minSpacing = kMinTopMargin + kMinBottomMargin + kMinTitleSubtitleSeparation + kMinSubtitleDateSeparation + kMinDateLocationSeparation
        let targetSpacing = kTargetTopMargin + kTargetBottomMargin + kTargetTitleSubtitleSeparation + kTargetSubtitleDateSeparation + kTargetDateLocationSeparation
        
        // if we are short space, try growing the container to a 3:2 aspect ratio from 2:1
        if (containerframe.height < totalHeightNeeded + targetSpacing) {
            //NSLog("increase container to 3:2 aspect ratio to fit large text")
            containerframe = growHeaderOverlayContainer(1.5)
        }
        
        // if we are still short space, try a 4:3 aspect ratio
        if (containerframe.height < totalHeightNeeded + targetSpacing) {
            //NSLog("increase container to 4:3 aspect ratio to fit large text")
            containerframe = growHeaderOverlayContainer(4.0/3.0)
        }
        
        // next try min spacing - if we still don't fit, need to start reducing field sizes...
        
        var titleHeightAllocated = titleHeightNeeded
        var subtitleHeightAllocated = subtitleHeightNeeded
        let dateHeightAllocated = dateHeightNeeded
        var locationHeightAllocated = locationHeightNeeded
        var locationIconWidth: CGFloat = 0.0
        if let locationIcon = locationIcon {
            if !locationIcon.hidden {
                locationIconWidth = locationIcon.bounds.width + 2*klocationIconOffset
            }
        }
        
        let spaceTarget = containerframe.height - minSpacing
        if locationHeightNeeded != 0.0 && (containerframe.height < totalHeightNeeded + minSpacing) {
            // still need space, try limiting location field...
            let reclaimable = shrinkLabelHeight(locationHeightNeeded, minAllocation: spaceTarget/4, width: headerOverlayContainer.bounds.width - locationIconWidth, label: locationLabel!)
            totalHeightNeeded -= reclaimable
            locationHeightAllocated -= reclaimable
            //NSLog("save space by decreasing allocation to location by \(reclaimable)")
        }
        
        if subtitleHeightNeeded != 0.0 && (containerframe.height < totalHeightNeeded + minSpacing) {
            // still need space, try limiting title field...
            let reclaimable = shrinkLabelHeight(titleHeightNeeded, minAllocation: spaceTarget/4, width: headerOverlayContainer.bounds.width, label: titleLabel!)
            totalHeightNeeded -= reclaimable
            titleHeightAllocated -= reclaimable
            //NSLog("save space by decreasing allocation to title by \(reclaimable)")
        }
        
        if (containerframe.height < totalHeightNeeded + minSpacing) {
            // still need space, try limiting notes field...
            let reclaimable = shrinkLabelHeight(subtitleHeightNeeded, minAllocation: spaceTarget/3, width: headerOverlayContainer.bounds.width, label: notesLabel!)
            totalHeightNeeded -= reclaimable
            subtitleHeightAllocated -= reclaimable
            //NSLog("save space by decreasing allocation to subtitle by \(reclaimable)")
        }
        
        // distribute space remaining
        var spaceRemaining: CGFloat = containerframe.height - totalHeightNeeded
        //NSLog("space remaining to distribute: \(spaceRemaining)")
        if spaceRemaining < 0.0 {
            spaceRemaining = 0.0
            NSLog("Error: Still too large!!")
        }
        
        var yAdvance = spaceRemaining == 0.0 ? kMinTopMargin : (kTargetTopMargin/targetSpacing) * spaceRemaining
        var nextFrame = CGRect(x: 0.0, y: yAdvance, width: containerframe.width, height: titleHeightAllocated)
        
        var heightUsed = centerLabelInTopFrame(titleLabel, frame: nextFrame).height
        var spacing = spaceRemaining == 0.0 ? kMinTitleSubtitleSeparation : (kTargetTitleSubtitleSeparation/targetSpacing) * spaceRemaining
        yAdvance = centerLabelInTopFrame(titleLabel, frame: nextFrame).height + spacing
        nextFrame.size.height = subtitleHeightAllocated
        nextFrame.origin.y += yAdvance
        
        heightUsed = centerLabelInTopFrame(notesLabel, frame: nextFrame).height
        spacing = spaceRemaining == 0.0 ? kMinSubtitleDateSeparation : (kTargetSubtitleDateSeparation/targetSpacing) * spaceRemaining
        yAdvance =  heightUsed + spacing
        nextFrame.size.height = dateHeightAllocated
        nextFrame.origin.y += yAdvance
        
        heightUsed = centerLabelInTopFrame(dateLabel, frame: nextFrame).height
        spacing = spaceRemaining == 0.0 ? kMinDateLocationSeparation : (kTargetDateLocationSeparation/targetSpacing) * spaceRemaining
        yAdvance =  heightUsed + spacing
        nextFrame.size.height = locationHeightAllocated
        nextFrame.origin.y += yAdvance
        
        if !locationLabel!.hidden {
            nextFrame.origin.x += locationIconWidth/2.0
            nextFrame.size.width -= locationIconWidth
            centerLabelInTopFrame(locationLabel, frame: nextFrame)
            if let locationIcon = locationIcon, locationLabel = locationLabel {
                // place icon to left of first line of location...
                var iconFrame: CGRect = locationIcon.bounds
                iconFrame.origin.x = ceil(locationLabel.frame.origin.x - iconFrame.width - klocationIconOffset)
                iconFrame.origin.y = locationLabel.frame.origin.y - 2.0
                locationIcon.frame = iconFrame
            }
        }
    }
    
    //
    // MARK: - Graph view
    //
    
    /// Reloads the graph - this should be called after the header has been laid out and the graph section size has been figured. Pass in edgeOffset to place the nut event other than in the center.
    private func configureGraphContainer(edgeOffset: CGFloat = 0.0) {
        //NSLog("EventDetailVC: configureGraphContainer")
        if (graphContainerView != nil) {
            graphContainerView?.removeFromSuperview();
            graphContainerView = nil;
        }
        graphContainerView = TidepoolGraphView.init(frame: graphLayerContainer.bounds, delegate: self, eventItem: eventItem!)
        if let graphContainerView = graphContainerView {
            graphContainerView.configureGraph(edgeOffset)
            graphLayerContainer.addSubview(graphContainerView)
            graphContainerView.loadGraphData()
       }
    }
    
    /// Reloads the graph as well as photo header background, but only if the graph has not been loaded already, or if the size of the graph section has changed.
    override func viewDidLayoutSubviews() {
        // self.view's direct subviews are laid out, force graph subview to layout its subviews:
        graphSectionView.setNeedsLayout()
        graphSectionView.layoutIfNeeded()
        //NSLog("EventDetailVC viewDidLayoutSubviews, graphSectionView: \(graphSectionView.frame.size)")
        if let graphContainerView = graphContainerView {
            if (graphContainerView.frame.size == graphSectionView.frame.size) {
                //NSLog("graph reconfigure skipped!")
                return
            }
            NSLog("Reconfigure graph, graphContainerView: \(graphContainerView.frame.size)")
        }
        configureGraphContainer()
        configurePhotoBackground()
    }
    
    //
    // MARK: - GraphContainerViewDelegate
    //
    //
    
    func containerCellUpdated() {
        let graphHasData = graphContainerView!.dataFound()
        if missingDataAdvisoryView.hidden && !graphHasData {
            // about to show missing data message...
            APIConnector.connector().trackMetric("Viewed 'No data' message")
        }
        missingDataAdvisoryView.hidden = graphHasData
    }

    func pinchZoomEnded() {
        //adjustZoomButtons()
        APIConnector.connector().trackMetric("Pinched to Zoom (Data Screen)")
    }
    
    private var currentCell: Int?
    func willDisplayGraphCell(cell: Int) {
        if let currentCell = currentCell {
            if cell > currentCell {
                APIConnector.connector().trackMetric("Swiped to Pan Left (Data Screen)")
            } else if cell < currentCell {
                APIConnector.connector().trackMetric("Swiped to Pan Right (Data Screen)")
            }
        }
        currentCell = cell
    }

    func dataPointTapped(dataPoint: GraphDataType, tapLocationInView: CGPoint) {
        var itemId: String?
        if let mealDataPoint = dataPoint as? MealGraphDataType {
            NSLog("tapped on meal!")
            itemId = mealDataPoint.id
        } else if let workoutDataPoint = dataPoint as? WorkoutGraphDataType {
            NSLog("tapped on workout!")
            itemId = workoutDataPoint.id
        }
        if let itemId = itemId {
            //NSLog("EventDetailVC: dataPointTapped")
            let nutEventItem = DatabaseUtils.getNutEventItemWithId(itemId)
            if let nutEventItem = nutEventItem {
                // if the user tapped on some other event, switch to viewing that one instead!
                if nutEventItem.time != eventTime {
                    switchedEvents = true
                    // conjure up a NutWorkout and NutEvent for this new item!
                    self.eventGroup = NutEvent(firstEvent: nutEventItem)
                    self.eventItem = self.eventGroup?.itemArray[0]
                    // update view to show the new event, centered...
                    configureDetailView()
                    layoutHeaderView()
                    // keep point that was tapped at the same offset in the view in the new graph by setting the graph center point to be at the same x offset in the view...
                    configureGraphContainer(tapLocationInView.x)
                    configurePhotoBackground()
                    // then animate to center...
                    if let graphContainerView = graphContainerView {
                        graphContainerView.centerGraphOnEvent(animated: true)
                    }
                }
            } else {
                NSLog("Couldn't find nut event item with id \(itemId)")
            }
        }
    }

}



