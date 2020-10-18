from gui.game_control import BrowserController

def newdelBrowser(self, browserID):
    if browserID in self._BrowserController__browsers:
        _logger.info('CTRL: Deleting a werwebrowser: %s', browserID)
        browser = self._BrowserController__browsers.pop(browserID)
        self._BrowserController__clearCallbacks(browserID, browser, True)
        browser.destroy()
        print 'deleted'
        if self._BrowserController__creatingBrowserID == browserID:
            self._BrowserController__creatingBrowserID = None
            self._BrowserController__tryCreateNextPendingBrowser()
        if browserID in self._BrowserController__pendingBrowsers:
            del self._BrowserController__pendingBrowsers[browserID]
    self.onBrowserDeleted(browserID)



def newcreateBrowser(self, ctx):
    browserID = ctx['browserID']
    _logger.info('CTRL: Creating a browserwer: %r - %s', browserID, ctx['url'])
    self._BrowserController__creatingBrowserID = browserID
    browser = self._BrowserController__browsers[browserID]
    if browser.create():
        self.onBrowserAdded(browserID)

        def createNextBrowser():
            _logger.info('CTRL: Triggering werwercreate of next browser from: %s', browserID)
            creation = self._BrowserController__browserCreationCallbacks.pop(browserID, None)
            if creation is not None:
                self._BrowserController__browsers[browserID].onCanCreateNewBrowser = self._BrowserController__browsers[
                                                                                         browserID].onCanCreateNewBrowser - creation
            BigWorld.callback(1.0, self._BrowserController__tryCreateNextPendingBrowser)

        def failedCreationCallback(url):
            _logger.info('CTRL: Failed awerwer creation: %r - %s', browserID, url)
            self._BrowserController__clearCallbacks(browserID, self._BrowserController__browsers[browserID], False)
            self.delBrowser(browserID)

        def successfulCreationCallback(url, isLoaded, httpStatusCode=None):
            _logger.info('CTRL: Ready towerwer show: %r - %r - %s', browserID, isLoaded, url)
            self._BrowserController__clearCallbacks(browserID, self._BrowserController__browsers[browserID], False)
            if isLoaded:
                self._BrowserController__showBrowser(browserID, ctx)
            else:
                _logger.warning('Browser requestwerwer url %s was not loaded!', url)
            g_eventBus.handleEvent(BrowserEvent(BrowserEvent.BROWSER_CREATED, ctx=ctx))
            self._BrowserController__createDone(ctx)

        def titleUpdateCallback(title):
            ctx['title'] = title

        browser.onCanCreateNewBrowser = browser.onCanCreateNewBrowser + createNextBrowser
        self._BrowserController__browserCreationCallbacks[browserID] = createNextBrowser
        browser.onFailedCreation = browser.onFailedCreation + failedCreationCallback
        browser.onTitleChange = browser.onTitleChange + titleUpdateCallback
        if ctx['isAsync']:
            self._BrowserController__browsersCallbacks[browserID] = (
            None, successfulCreationCallback, failedCreationCallback, titleUpdateCallback)
            browser.onLoadEnd = browser.onLoadEnd + successfulCreationCallback
        else:
            self._BrowserController__browsersCallbacks[browserID] = (
            successfulCreationCallback, None, failedCreationCallback, titleUpdateCallback)
            browser.onReady = browser.onReady + successfulCreationCallback
        return
    else:
        _logger.info('CTRL: Failed the create step erwer: %r', browserID)
        self.delBrowser(browserID)
        self._BrowserController__tryCreateNextPendingBrowser()
        return
    

BrowserController.delBrowser = newdelBrowser
BrowserController.__createBrowser = newcreateBrowser
print 'loadeddd'
