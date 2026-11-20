package de.audi.app.combi.bap.app.audio;

import com.mhi2.androidadio.AAJavaBridge;
import de.audi.app.bap.fw.AbstractBAPModuleFSG;
import de.audi.app.bap.fw.IBAPModuleInitializationManager;
import de.audi.app.bap.fw.arrays.ArrayHandler;
import de.audi.app.bap.fw.functionsync.IFunctionSynchronizationHandler;
import de.audi.app.bap.fw.functiontypes.BAPFunctionArrayFSG;
import de.audi.app.bap.fw.functiontypes.BAPFunctionMethodFSG;
import de.audi.app.bap.fw.functiontypes.BAPFunctionPropertyFSG;
import de.audi.app.combi.bap.app.audio.list.MediaBrowserListHandler;
import de.audi.app.combi.bap.app.audio.list.SourceListHandler;
import de.audi.app.combi.bap.app.kombipictures.IPictureManager;
import de.audi.app.combi.bap.app.kombipictures.IPictureProvider;
import de.audi.app.combi.bap.fw.AbstractCombiModule;
import de.audi.atip.interapp.bap.BAPServiceListener;
import de.audi.atip.interapp.combi.bap.audio.CombiBAPServiceMedia;
import de.audi.atip.interapp.combi.bap.audio.CombiBAPServiceMediaListener;
import de.audi.atip.interapp.combi.bap.audio.data.CombiBAPAudioSource;
import de.audi.app.combi.bap.app.audio.CombiBAPAudioListStates;
import de.audi.atip.interapp.combi.bap.audio.data.CombiBAPCurrentStationInfo;
import de.audi.atip.interapp.combi.bap.audio.data.CombiBAPMediaBrowserListEntry;
import de.audi.atip.interapp.combi.bap.audio.data.PlayPosition;
import de.audi.atip.log.LogChannel;
import de.vw.mib.bap.datatypes.BAPString;
import de.vw.mib.bap.generated.audiosd.serializer.ActiveSource_Status;
import de.vw.mib.bap.generated.audiosd.serializer.MediaBrowserControl_Result;
import de.vw.mib.bap.generated.audiosd.serializer.MediaBrowser_FolderLevel_Status;
import de.vw.mib.bap.generated.audiosd.serializer.MediaImportState_Status;
import de.vw.mib.bap.generated.audiosd.serializer.MediaPath_Status;
import de.vw.mib.bap.generated.audiosd.serializer.PlayPosition_Status;
import de.vw.mib.bap.requests.ResultMethod;
import de.vw.mib.bap.requests.StatusProperty;
import edu.emory.mathcs.backport.java.util.concurrent.Callable;
import edu.emory.mathcs.backport.java.util.concurrent.Executors;
import edu.emory.mathcs.backport.java.util.concurrent.ScheduledExecutorService;
import edu.emory.mathcs.backport.java.util.concurrent.TimeUnit;
import java.util.HashMap;
import java.util.Map;
import org.dsi.ifc.global.ResourceLocator;

public class AppConnectorMedia extends de.audi.app.combi.bap.app.audio.AbstractAppConnectorAudio implements CombiBAPServiceMedia {

    private static final int TRACK_CHANGE_TO_NEW_FOLDER_TIME_WINDOW_MS = 50;

    private final ScheduledExecutorService executor;
    private final CoverArtProvider pictureProvider;

    public AppConnectorMedia(CombiModuleAudio module) {
        super(module);
        executor = Executors.newSingleThreadScheduledExecutor();
        pictureProvider = new CoverArtProvider(this);
        module.getPictureManager().registerPictureProvider(0, pictureProvider);
        try {
            com.mhi2.androidadio.AAJavaBridge.setCombiModule(module);
            com.mhi2.androidadio.AAJavaBridge.setPictureManager(module.getPictureManager());
        } catch (Throwable t) {}
    }

    public void setAppServiceListener(BAPServiceListener listener) {
        super.setAppServiceListener(listener);
        if (listener == null) {
            AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
            if (moduleFsg != null) {
                BAPServiceListener existing = moduleFsg.getAppServiceListener("Tuner");
                if (existing == null) {
                    IBAPModuleInitializationManager initMgr = moduleFsg.getInitializationManager();
                    if (initMgr != null) {
                        initMgr.notifyAppServiceChanged(false);
                    }
                } else {
                    IBAPModuleInitializationManager initMgr = moduleFsg.getInitializationManager();
                    if (initMgr != null) {
                        initMgr.notifyAppServiceChanged(true);
                    }
                }
            }
        } else {
            AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
            if (moduleFsg != null) {
                IBAPModuleInitializationManager initMgr = moduleFsg.getInitializationManager();
                if (initMgr != null) {
                    initMgr.notifyAppServiceChanged(true);
                }
            }
        }
    }

    protected int getAudioApplication() {
        return 1;
    }

    protected java.lang.String getAudioApplicationName() {
        return "Media";
    }

    protected boolean isAudioApplicationInFocus() {
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        if (moduleFsg != null) {
            CombiModuleAudio combiModule = (CombiModuleAudio) moduleFsg;
            de.audi.app.combi.bap.app.audio.AudioApplicationInFocusHandler handler = combiModule.getAudioApplicationFocusHandler();
            if (handler != null) {
                return handler.isMediaInFocus();
            }
        }
        return false;
    }

    public void updateActiveSource(int sourceType, int slotNumber, int partitionNumber, boolean mediaBrowserListAvailable, boolean presetListAvailable, int listState) {
        CombiBAPAudioSource source = new CombiBAPAudioSource();
        source.setSourceType(sourceType);
        source.setSlotNumber(slotNumber);
        source.setPartitionNumber(partitionNumber);
        CombiBAPAudioListStates states = new CombiBAPAudioListStates();
        states.setMediaBrowserListAvailable(mediaBrowserListAvailable);
        states.setPresetListAvailable(presetListAvailable);
        states.setListState(listState);
        updateActiveSource(source, states);
    }

    protected void sendSourceChangeRelatedProperties() {
        super.sendSourceChangeRelatedProperties();
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        if (moduleFsg != null) {
            BAPFunctionPropertyFSG func37 = moduleFsg.getBAPFunctionPropertyFSG(37);
            if (func37 != null) {
                StatusProperty status = func37.getLastStatus();
                if (status != null) {
                    func37.sendStatusIfChanged(status);
                }
            }
            BAPFunctionPropertyFSG func35 = moduleFsg.getBAPFunctionPropertyFSG(35);
            if (func35 != null) {
                StatusProperty status = func35.getLastStatus();
                if (status != null) {
                    func35.sendStatusIfChanged(status);
                }
            }
        }
    }

    public void updateCurrentStation(CombiBAPCurrentStationInfo info) {
        if (logChannel != null) {
            logChannel.log(10000000, "[AppConnectorMedia#updateCurrentStation] called", new Long(0));
        }
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        int sourceType = 0;
        if (moduleFsg != null) {
            BAPFunctionPropertyFSG func16 = moduleFsg.getBAPFunctionPropertyFSG(16);
            if (func16 != null) {
                StatusProperty status = func16.getLastStatus();
                if (status instanceof ActiveSource_Status) {
                    ActiveSource_Status activeSource = (ActiveSource_Status) status;
                    sourceType = activeSource.sourceType;
                }
            }
        }
        ResourceLocator locator = new ResourceLocator(info.getPictureID(), info.getPictureURL());
        if (pictureProvider != null) {
            pictureProvider.clearMapping();
        }
        if (pictureProvider != null) {
            pictureProvider.addToMapping(new Long(info.getListRef()), locator);
        }
        if (moduleFsg != null) {
            IPictureManager pictureManager = ((AbstractCombiModule) moduleFsg).getPictureManager();
            if (pictureManager != null) {
                pictureManager.responseCoverArt(new Long(info.getListRef()), sourceType, locator, true);
            }
        }
        super.updateCurrentStation(info);
    }

    public void updateSourceListMedia(int[] sourceTypes, CombiBAPAudioSource[][] sources) {
        if (logChannel != null) {
            logChannel.log(1000000, "[AppConnectorMedia#updateSourceListMedia] called (specified sourceTypes)", new Long(0));
        }
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        if (moduleFsg != null) {
            BAPFunctionArrayFSG func32 = moduleFsg.getBAPFunctionArrayFSG(32);
            if (func32 != null) {
                ArrayHandler handler = func32.getArrayHandler();
                if (handler instanceof SourceListHandler) {
                    SourceListHandler listHandler = (SourceListHandler) handler;
                    listHandler.updateSources(1, sourceTypes, sources);
                }
            }
        }
    }

    public void goToResult(int resultType, int result) {
        if (logChannel != null) {
            logChannel.log(1000000, "[AppConnectorMedia#goToResult] called (result=%1)", new Long(result));
        }
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        if (moduleFsg != null) {
            BAPFunctionMethodFSG func38 = moduleFsg.getBAPFunctionMethodFSG(38);
            if (func38 != null) {
                ResultMethod serializer = moduleFsg.createResultSerializer(38);
                if (serializer instanceof MediaBrowserControl_Result) {
                    MediaBrowserControl_Result browserResult = (MediaBrowserControl_Result) serializer;
                    browserResult.browserControlResult = result;
                    func38.resultREQ(browserResult);
                }
            }
        }
    }

    public void trackChangeIsComing() {
        if (logChannel != null) {
            logChannel.log(1000000, "[AppConnectorMedia#trackChangeIsComing] called", new Long(0));
        }
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        if (moduleFsg != null) {
            IFunctionSynchronizationHandler syncHandler = moduleFsg.getFunctionSynchronizationHandler();
            if (syncHandler != null) {
                syncHandler.startSync(6);
            }
        }
    }

    public void updateBrowserListSize(final int listSize) {
        if (executor != null) {
            executor.schedule(new Callable() {
                public Object call() {
                    if (logChannel != null) {
                        logChannel.log(1000000, "[AppConnectorMedia#updateBrowserListSize] called (listSize=%1)", new Long(listSize));
                    }
                    AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) AppConnectorMedia.this.moduleFsg;
                    if (moduleFsg != null) {
                        ArrayHandler handler = moduleFsg.getBAPFunctionArrayFSG(36).getArrayHandler();
                        if (handler != null) {
                            MediaBrowserListHandler listHandler = (MediaBrowserListHandler) handler;
                            listHandler.notifyListSizeChanged(listSize);
                        }
                    }
                    return null;
                }
            }, 50L, TimeUnit.MILLISECONDS);
        }
    }

    public void updateCurrentBrowseFolder(int folderType, java.lang.String folderPath, int folderLevel, int refMediaBrowser, int refMediaBrowserAbsolutePosition) {
        if (logChannel != null) {
            logChannel.log(1000000, "[AppConnectorMedia#updateCurrentBrowseFolder] called (folderPath=%1, folderType=%2)", folderPath, new Long(folderType));
        }
        if (logChannel != null) {
            logChannel.log(1000000, "[AppConnectorMedia#updateCurrentBrowseFolder] ... folderLevel=%1, refMediaBrowser=%2, refMediaBrowserAbsolutePosition=%3)", new Long(folderLevel), new Long(refMediaBrowser), new Long(refMediaBrowserAbsolutePosition));
        }
        MediaPath_Status pathStatus = new MediaPath_Status();
        pathStatus.folder_Type = folderType;
        if (pathStatus.path != null) {
            pathStatus.path.setContent(folderPath);
        }
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        if (moduleFsg != null) {
            BAPFunctionPropertyFSG func37 = moduleFsg.getBAPFunctionPropertyFSG(37);
            if (func37 != null) {
                func37.sendStatusIfChanged(pathStatus);
            }
        }
        MediaBrowser_FolderLevel_Status folderStatus = new MediaBrowser_FolderLevel_Status();
        folderStatus.folderLevel = folderLevel;
        folderStatus.ref_MediaBrowser = refMediaBrowser;
        folderStatus.ref_MediaBrowser_absolutePosition = refMediaBrowserAbsolutePosition;
        if (moduleFsg != null) {
            BAPFunctionPropertyFSG func35 = moduleFsg.getBAPFunctionPropertyFSG(35);
            if (func35 != null) {
                func35.sendStatusIfChanged(folderStatus);
            }
        }
    }

    public void responseMediaBrowserList(int taID, CombiBAPMediaBrowserListEntry[] entries) {
        if (logChannel != null) {
            logChannel.log(1000000, "[AppConnectorMedia#responseMediaBrowserList] taID=%1, noOfListEntries=%2", new Long(taID), new Long(entries.length));
        }
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        if (moduleFsg != null) {
            BAPFunctionArrayFSG func36 = moduleFsg.getBAPFunctionArrayFSG(36);
            if (func36 != null) {
                ArrayHandler handler = func36.getArrayHandler();
                if (handler != null) {
                    handler.responseListElements(taID, entries);
                }
            }
        }
    }

    public void updatePlaybackFolder(boolean isPlaybackFolder) {
        if (logChannel != null) {
            logChannel.log(1000000, "[AppConnectorMedia#updatePlaybackFolder] isPlaybackFolder=%1", new Boolean(isPlaybackFolder));
        }
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        if (moduleFsg != null) {
            BAPFunctionArrayFSG func36 = moduleFsg.getBAPFunctionArrayFSG(36);
            if (func36 != null) {
                ArrayHandler handler = func36.getArrayHandler();
                if (handler instanceof MediaBrowserListHandler) {
                    MediaBrowserListHandler listHandler = (MediaBrowserListHandler) handler;
                    listHandler.setPlaybackFolder(isPlaybackFolder);
                }
            }
        }
    }

    public void updateMediaImportState(int sourceType, int instanceID, boolean importActive, int progress) {
        if (logChannel != null) {
            logChannel.log(1000000, "[AppConnectorMedia#updateMediaImportState] sourceType=%1, instanceID=%2", new Long(sourceType), new Long(instanceID));
        }
        if (logChannel != null) {
            logChannel.log(1000000, "[AppConnectorMedia#updateMediaImportState] importActive=%1, progress=%2", new Boolean(importActive), new Long(progress));
        }
        MediaImportState_Status importStatus = new MediaImportState_Status();
        importStatus.sourceType = sourceType;
        importStatus.instance_Id = instanceID;
        importStatus.state = importActive ? 1 : 0;
        importStatus.progress = progress;
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        if (moduleFsg != null) {
            BAPFunctionPropertyFSG func46 = moduleFsg.getBAPFunctionPropertyFSG(46);
            if (func46 != null) {
                func46.sendStatusIfChanged(importStatus);
            }
        }
    }

    public void responseCoverArt(long listRef, int instanceId, java.lang.String coverArtUrl, int pictureId) {
        AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
        if (moduleFsg != null) {
            IPictureManager pictureManager = ((AbstractCombiModule) moduleFsg).getPictureManager();
            if (pictureManager != null) {
                ResourceLocator locator = new ResourceLocator(pictureId, coverArtUrl);
                pictureManager.responseCoverArt(new Long(listRef), instanceId, locator, false);
            }
        }
    }

    public void updatePlayPosition(PlayPosition playPosition) {
        if (logChannel != null) {
            logChannel.log(10000000, "[AppConnectorMedia#updatePlayPosition] %1", playPosition);
        }
        if (isAudioApplicationInFocus()) {
            PlayPosition_Status status = new PlayPosition_Status();
            status.timePosition = playPosition.getTimePosition().getTimeInSeconds();
            status.totalPlayTime = playPosition.getTotalPlayTime().getTimeInSeconds();
            if (status.attributes != null) {
                status.attributes.variableBitRateActive = playPosition.isVariableBitRate();
            }
            AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) this.moduleFsg;
            if (moduleFsg != null) {
                BAPFunctionPropertyFSG func52 = moduleFsg.getBAPFunctionPropertyFSG(52);
                if (func52 != null) {
                    func52.sendStatusIfChanged(status);
                }
            }
        } else {
            if (logChannel != null) {
                logChannel.log(10000000, "[AppConnectorMedia#updatePlayPosition] application not in focus; don't send playPosition", new Long(0));
            }
        }
    }

    class CoverArtProvider implements IPictureProvider {

        private final Map id2pictureURL;

        CoverArtProvider(AppConnectorMedia appConnectorMedia) {
            id2pictureURL = new HashMap();
        }

        public void requestPicture(long bapEntryID) {
            requestPicture(bapEntryID, 255);
        }

        public void requestPicture(long bapEntryID, int instanceId) {
            java.lang.Long key = new java.lang.Long(bapEntryID);
            if (id2pictureURL.containsKey(key)) {
                AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) AppConnectorMedia.this.moduleFsg;
                if (moduleFsg != null) {
                    IPictureManager pictureManager = ((AbstractCombiModule) moduleFsg).getPictureManager();
                    if (pictureManager != null) {
                        Object locator = id2pictureURL.get(key);
                        if (locator instanceof ResourceLocator) {
                            pictureManager.responseCoverArt(new Long(bapEntryID), instanceId, (ResourceLocator) locator, false);
                        }
                    }
                }
            } else {
                AbstractBAPModuleFSG moduleFsg = (AbstractBAPModuleFSG) AppConnectorMedia.this.moduleFsg;
                if (moduleFsg != null) {
                    BAPServiceListener listener = appServiceListener;
                    if (listener instanceof CombiBAPServiceMediaListener) {
                        if (logChannel != null) {
                            logChannel.log(10000000, "[AppConnectorMedia.CoverArtProvider#requestPicture] call media service 'requestCoverArt(bapEntryID=%1)'", new java.lang.Long(bapEntryID));
                        }
                        IPictureManager pictureManager = ((AbstractCombiModule) moduleFsg).getPictureManager();
                        if (pictureManager != null) {
                            pictureManager.responseCoverArt(new Long(bapEntryID), instanceId, null, false);
                        }
                    }
                }
            }
        }

        public void addToMapping(long listRef, ResourceLocator locator) {
            id2pictureURL.put(new java.lang.Long(listRef), locator);
        }

        public void clearMapping() {
            id2pictureURL.clear();
        }
    }
}
