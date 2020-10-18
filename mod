import logging
import BigWorld
import Event
from WebBrowser import WebBrowser
from adisp import async
from adisp import process
from gui import GUI_SETTINGS
from gui.Scaleform.Waiting import Waiting
from gui.Scaleform.daapi.settings.views import VIEW_ALIAS
from gui.game_control.browser_filters import getFilters as _getGlobalFilters
from gui.game_control.gc_constants import BROWSER
from gui.game_control.links import URLMacros
from gui.shared import EVENT_BUS_SCOPE
from gui.shared import g_eventBus
from gui.shared.events import LoadViewEvent
from gui.shared.events import BrowserEvent
from gui.shared.utils.functions import getViewName
from helpers import dependency
from ids_generators import SequenceIDGenerator
from skeletons.gui.app_loader import IAppLoader
from skeletons.gui.game_control import IBrowserController
from soft_exception import SoftException
_logger = logging.getLogger(__name__)
class BrowserController(IBrowserController):
    _BROWSER_TEXTURE = 'BrowserBg'
    _ALT_BROWSER_TEXTURE = 'AltBrowserBg'
    def __init__(self):
        super(BrowserController, self).__init__()
        self._BrowserController__browsers = {}
        self._BrowserController__browsersCallbacks = {}
        self._BrowserController__browserCreationCallbacks = {}
        self._BrowserController__browserIDGenerator = SequenceIDGenerator()
        self._BrowserController__eventMgr = Event.EventManager()
        self.onBrowserAdded = Event.Event(self._BrowserController__eventMgr)
        self.onBrowserDeleted = Event.Event(self._BrowserController__eventMgr)
        self._BrowserController__urlMacros = URLMacros()
        self._BrowserController__pendingBrowsers = {}
        self._BrowserController__creatingBrowserID = None
        self._BrowserController__filters = _getGlobalFilters()

    def fini(self):
        self._BrowserController__filters = None
        self._BrowserController__eventMgr.clear()
        self._BrowserController__eventMgr = None
        self._BrowserController__urlMacros.clear()
        self._BrowserController__urlMacros = None
        self._BrowserController__browsersCallbacks.clear()
        self._BrowserController__browsersCallbacks = None
        self._BrowserController__browsers.clear()
        self._BrowserController__browsers = None
        self._BrowserController__pendingBrowsers.clear()
        self._BrowserController__pendingBrowsers = None
        self._BrowserController__browserIDGenerator = None
        super(BrowserController, self).fini()

    def onAvatarBecomePlayer(self):
        self._BrowserController__stop()
        print 'avatar'

    def onDisconnected(self):
        self._BrowserController__stop()
        print 'disconected'

    def onLobbyStarted(self, ctx):
        BigWorld.createBrowser()

    def addFilterHandler(self, handler):
        self._BrowserController__filters.add(handler)

    def removeFilterHandler(self, handler):
        self._BrowserController__filters.discard(handler)

    @process
    @async
    def load(self, url = None, title = None, showActionBtn = True, showWaiting = True, browserID = None, isAsync = False, browserSize = None, isDefault = True, callback = None, showCloseBtn = False, useBrowserWindow = True, isModal = False, showCreateWaiting = False, handlers = None, showBrowserCallback = None, isSolidBorder = False):
        if showCreateWaiting:
            Waiting.show('browser/init')
        url = yield self._BrowserController__urlMacros.parse(url or GUI_SETTINGS.browser.url)
        suffix = yield self._BrowserController__urlMacros.parse(GUI_SETTINGS.browser.params)
        concatenator = '&' if '?' in url else '?'
        if suffix not in url:
            url = concatenator.join([url, suffix])
        size = browserSize or BROWSER.SIZE
        webBrowserID = browserID
        if browserID is None:
            browserID = self._BrowserController__browserIDGenerator.next()
            webBrowserID = browserID
        elif type(browserID) is not int:
            webBrowserID = self._BrowserController__browserIDGenerator.next()
        ctx = {'showCloseBtn': showCloseBtn, 'showBrowserCallback': showBrowserCallback, 'showWaiting': showWaiting, 'url': url, 'title': title, 'showCreateWaiting': showCreateWaiting, 'browserID': browserID, 'alias': VIEW_ALIAS.BROWSER_WINDOW_MODAL if isModal else VIEW_ALIAS.BROWSER_WINDOW, 'isAsync': isAsync, 'showActionBtn': showActionBtn, 'handlers': handlers, 'showWindow': useBrowserWindow, 'isSolidBorder': isSolidBorder, 'size': size}
        if browserID not in self._BrowserController__browsers and browserID not in self._BrowserController__pendingBrowsers:
            texture = self._BROWSER_TEXTURE
            appLoader = dependency.instance(IAppLoader)
            app = appLoader.getApp()
            if app is None:
                raise SoftException('Application can not be None')
            else:
                browser = WebBrowser(webBrowserID, app, texture, size, url, handlers = self._BrowserController__filters)
                self._BrowserController__browsers[browserID] = browser
                if self._BrowserController__isCreatingBrowser():
                    _logger.info('CTRL: Queueing a browser creation wtf: %r - %s', browserID, url)
                    self._BrowserController__pendingBrowsers[browserID] = ctx
                else:
                    self._BrowserController__createBrowser(ctx)
        elif browserID in self._BrowserController__pendingBrowsers:
            _logger.info('CTRL: Re-queuing a browser creation wtf, overriding: %r - %s', browserID, url)
            self._BrowserController__pendingBrowsers[browserID] = ctx
        elif browserID in self._BrowserController__browsers:
            _logger.info('CTRL: Re-navigating an existing browser wtf: %r - %s', browserID, url)
            browser = self._BrowserController__browsers[browserID]
            browser.navigate(url)
            browser.changeTitle(title)
        callback(browserID)

    def getAllBrowsers(self):
        return self._BrowserController__browsers

    def getBrowser(self, browserID):
        return self._BrowserController__browsers.get(browserID)

    def delBrowser(self, browserID):
        if browserID in self._BrowserController__browsers:
            _logger.info('CTRL: Deleting a browser WTF: %s', browserID)
            browser = self._BrowserController__browsers.pop(browserID)
            self._BrowserController__clearCallbacks(browserID, browser, True)
            print 'browser deleted'
            if self._BrowserController__creatingBrowserID == browserID:
                self._BrowserController__creatingBrowserID = None
                self._BrowserController__tryCreateNextPendingBrowser()
            if browserID in self._BrowserController__pendingBrowsers:
                del self._BrowserController__pendingBrowsers[browserID]
        self.onBrowserDeleted(browserID)

    def __isCreatingBrowser(self):
        return self._BrowserController__creatingBrowserID is not None

    def __createDone(self, ctx):
        _logger.info('CTRL: Finished creating a browser WTH: %s', self._BrowserController__creatingBrowserID)
        if ctx['showCreateWaiting']:
            Waiting.hide('browser/init')

    def __tryCreateNextPendingBrowser(self):
        self._BrowserController__creatingBrowserID = None
        if self._BrowserController__pendingBrowsers:
            nextCtx = self._BrowserController__pendingBrowsers.popitem()[1]
            self._BrowserController__createBrowser(nextCtx)

    def __createBrowser(self, ctx):
        browserID = ctx['browserID']
        _logger.info('CTRL: Creating a browser wtf: %r - %s', browserID, ctx['url'])
        self._BrowserController__creatingBrowserID = browserID
        browser = self._BrowserController__browsers[browserID]
        if browser.create():
            self.onBrowserAdded(browserID)
            def createNextBrowser():
                _logger.info('CTRL: Triggering create of next browser from wtf: %s', browserID)
                creation = self._BrowserController__browserCreationCallbacks.pop(browserID, None)
                if creation is not None:
                    self._BrowserController__browsers[browserID].onCanCreateNewBrowser = self._BrowserController__browsers[browserID].onCanCreateNewBrowser - creation
                BigWorld.callback(1.0, self._BrowserController__tryCreateNextPendingBrowser)

            def failedCreationCallback(url):
                _logger.info('CTRL: Failed a creation wtf: %r - %s', browserID, url)
                self._BrowserController__clearCallbacks(browserID, self._BrowserController__browsers[browserID], False)
                self.delBrowser(browserID)

            def successfulCreationCallback(url, isLoaded, httpStatusCode = None):
                _logger.info('CTRL: Ready to show wtf: %r - %r - %s', browserID, isLoaded, url)
                self._BrowserController__clearCallbacks(browserID, self._BrowserController__browsers[browserID], False)
                if isLoaded:
                    self._BrowserController__showBrowser(browserID, ctx)
                else:
                    _logger.warning('Browser request url %s was not loaded wtf!', url)
                g_eventBus.handleEvent(BrowserEvent(BrowserEvent.BROWSER_CREATED, ctx = ctx))
                self._BrowserController__createDone(ctx)

            def titleUpdateCallback(title):
                ctx['title'] = title

            browser.onCanCreateNewBrowser = browser.onCanCreateNewBrowser + createNextBrowser
            self._BrowserController__browserCreationCallbacks[browserID] = createNextBrowser
            browser.onFailedCreation = browser.onFailedCreation + failedCreationCallback
            browser.onTitleChange = browser.onTitleChange + titleUpdateCallback
            if ctx['isAsync']:
                self._BrowserController__browsersCallbacks[browserID] = (None, successfulCreationCallback, failedCreationCallback, titleUpdateCallback)
                browser.onLoadEnd = browser.onLoadEnd + successfulCreationCallback
            else:
                self._BrowserController__browsersCallbacks[browserID] = (successfulCreationCallback, None, failedCreationCallback, titleUpdateCallback)
                browser.onReady = browser.onReady + successfulCreationCallback
            return
        else:
            _logger.info('CTRL: Failed the create step wtf: %r', browserID)
            self.delBrowser(browserID)
            self._BrowserController__tryCreateNextPendingBrowser()
            return

    def __stop(self):
        while self._BrowserController__browsers:
            browserID, browser = self._BrowserController__browsers.popitem()
            self._BrowserController__clearCallbacks(browserID, browser, True)
            print 'stopeed'

    def __clearCallbacks(self, browserID, browser, incDelayedCreation):
        ready, loadEnd, failed, title = self._BrowserController__browsersCallbacks.pop(browserID, (None, None, None, None))
        if browser is not None:
            if failed is not None:
                browser.onFailedCreation = browser.onFailedCreation - failed
            if ready is not None:
                browser.onReady = browser.onReady - ready
            if loadEnd is not None:
                browser.onLoadEnd = browser.onLoadEnd - loadEnd
            if title is not None:
                browser.onTitleChange = browser.onTitleChange - title
        if incDelayedCreation:
            creation = self._BrowserController__browserCreationCallbacks.pop(browserID, None)
            if browser is not None and creation is not None:
                browser.onCanCreateNewBrowser = browser.onCanCreateNewBrowser - creation

    def __showBrowser(self, browserID, ctx):
        _logger.info('CTRL: Showing a browser wth: %r - %s', browserID, ctx['url'])
        if ctx.get('showWindow'):
            alias = ctx['alias']
            g_eventBus.handleEvent(LoadViewEvent(alias, getViewName(alias, browserID), ctx = ctx), EVENT_BUS_SCOPE.LOBBY)
        showBrowserCallback = ctx.get('showBrowserCallback')
        if showBrowserCallback:
            showBrowserCallback()

print 'loaded'
