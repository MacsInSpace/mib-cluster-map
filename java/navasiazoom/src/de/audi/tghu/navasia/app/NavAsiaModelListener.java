package de.audi.tghu.navasia.app;

import de.audi.atip.hmi.model.ButtonListener;
import de.audi.atip.hmi.model.ChoiceListener;
import de.audi.atip.hmi.model.IntegerListCell;
import de.audi.atip.hmi.model.ListListener;
import de.audi.atip.hmi.model.ListRow;
import de.audi.atip.hmi.model.MatchspellerListenerAsia;
import de.audi.atip.hmi.model.RangeListener;
import de.audi.atip.hmi.model.SlidingListModelListener;
import de.audi.atip.hmi.model.SpellerListenerAsia;
import de.audi.atip.hmi.model.SpellerModel;
import de.audi.atip.hmi.model.TooltipListener;
import de.audi.atip.hmi.model.VirtualButtonListener;
import de.audi.atip.hmi.modelaccess.ButtonModelApp;
import de.audi.atip.hmi.modelaccess.ChoiceModelApp;
import de.audi.atip.hmi.modelaccess.LabelModelApp;
import de.audi.atip.hmi.modelaccess.ListModelApp;
import de.audi.atip.hmi.modelaccess.MatchspellerModelAsiaApp;
import de.audi.atip.hmi.modelaccess.RangeModelApp;
import de.audi.atip.hmi.modelaccess.SlidingListModelApp;
import de.audi.atip.hmi.modelaccess.SpellerModelAsiaApp;
import de.audi.atip.hmi.modelaccess.TooltipModelApp;
import de.audi.atip.hmi.modelaccess.VirtualButtonModelApp;
import de.audi.atip.log.LogChannel;
import de.audi.atip.timer.Timer;
import de.audi.atip.timer.TimerListener;
import local.clustermap.NavAsiaZoom;

/*
 * mib-cluster-map: a replacement, written for this project, of the model
 * listener of the Asia navigation on MHI2_CN_AU57x_K1006_2 (lsd.jxe 43229093
 * bytes), loaded ahead of lsd.jxe from
 * /eso/hmi/lsd/jars/ClusterMapNavAsiaZoom.jar.
 *
 * That interface has no Java cockpit map: every roller and encoder step of
 * the navigation's models comes through increment and decrement here and goes
 * to the native navigation. This class keeps the stock one's name, members
 * and behaviour, method for method, and adds one call: each step is first
 * shown to NavAsiaZoom, which logs it and, once the cockpit roller's model ID
 * is configured, sends it to the CarPlay map while that covers the cockpit.
 *
 * Everything it calls in lsd.jxe is public, and NavAsiaApp only calls its
 * public constructor, so it does not depend on J9 counting a class from a jar
 * as part of lsd.jxe's package.
 *
 * Only for this one HMI build: the installer checks lsd.jxe's size first.
 * tests/navasiazoom_check.sh compares this class with the stock one.
 */
public class NavAsiaModelListener implements ButtonListener, ChoiceListener, RangeListener, SpellerListenerAsia,
        ListListener, MatchspellerListenerAsia, SlidingListModelListener, VirtualButtonListener, TimerListener,
        TooltipListener {
    private NavAsiaModelBank modelBank;
    private NavAsiaApp appNavAsia;
    private LogChannel log;

    public NavAsiaModelListener(NavAsiaModelBank modelBank, NavAsiaApp appNavAsia, LogChannel log) {
        this.modelBank = modelBank;
        this.appNavAsia = appNavAsia;
        this.log = log;
        ListConfigurator.configureLists(modelBank);
        this.registerListeners();
        SpellerConfigurator.configureSpellers(modelBank);
        ((RangeModelApp) modelBank.getModel(81139)).setPressed(true);
        ((RangeModelApp) modelBank.getModel(80959)).setValue(5);
        ((RangeModelApp) modelBank.getModel(81141)).setValue(5);
        ((RangeModelApp) modelBank.getModel(81151)).setValue(5);
        ((RangeModelApp) modelBank.getModel(81040)).setValue(5);
        ((RangeModelApp) modelBank.getModel(80836)).setValue(5);
        ((RangeModelApp) modelBank.getModel(80864)).setValue(5);
        ((RangeModelApp) modelBank.getModel(81366)).setValue(5);
        ((LabelModelApp) modelBank.getModel(81370)).setStatus(0);
        ((RangeModelApp) modelBank.getModel(80414)).setValue(5);
        ((ListModelApp) modelBank.getModel(80343)).addHint(12);
        ((ListModelApp) modelBank.getModel(81583)).addHint(12);
        ((ListModelApp) modelBank.getModel(81585)).addHint(12);
        ((ListModelApp) modelBank.getModel(80792)).addHint(12);
        ((ListModelApp) modelBank.getModel(80796)).addHint(12);
        ((ChoiceModelApp) modelBank.getModel(80388)).setValue(-1);
        ((ChoiceModelApp) modelBank.getModel(80941)).setValue(-1);
        ((ChoiceModelApp) modelBank.getModel(80131)).setValue(-1);
        ((RangeModelApp) modelBank.getModel(81096)).setMedialPosition(6);
        ((RangeModelApp) modelBank.getModel(81052)).setMedialPosition(4);
        ((ListModelApp) modelBank.getModel(81463)).setMaxColumns(4);
        ((ChoiceModelApp) modelBank.getModel(81789)).setValue(4);
        ((RangeModelApp) modelBank.getModel(81797)).setValue(5);
        ((ListModelApp) modelBank.getModel(81809)).setMaxColumns(20);
        ((ListModelApp) modelBank.getModel(81809)).setMaxRows(1);
        ((ListModelApp) modelBank.getModel(81898)).setMaxColumns(20);
        ((ListModelApp) modelBank.getModel(81898)).setMaxRows(1);
        ((ListModelApp) modelBank.getModel(81902)).setMaxColumns(20);
        ((ListModelApp) modelBank.getModel(81902)).setMaxRows(1);
        ((ListModelApp) modelBank.getModel(80707)).setMaxColumns(20);
        ((ListModelApp) modelBank.getModel(80707)).setMaxRows(1);
        ((RangeModelApp) modelBank.getModel(82045)).setValue(5);
        ((ListModelApp) modelBank.getModel(82003)).setMaxColumns(20);
        ((ListModelApp) modelBank.getModel(82003)).setMaxRows(1);
        ((ListModelApp) modelBank.getModel(82089)).setMaxColumns(20);
        ((ListModelApp) modelBank.getModel(82089)).setMaxRows(1);
        ((RangeModelApp) modelBank.getModel(81620)).setValue(5);
        ((RangeModelApp) modelBank.getModel(81618)).setValue(5);
        NavAsiaApp.getFramework().getSysApp().getButtonModelApp(831).setStatus(0);
        ((RangeModelApp) modelBank.getModel(80475)).setValue(5);
        ((ChoiceModelApp) modelBank.getModel(81939)).setValue(6);
        ((ChoiceModelApp) modelBank.getModel(81940)).setValue(6);
        ((ChoiceModelApp) modelBank.getModel(81941)).setValue(6);
        ((ChoiceModelApp) modelBank.getModel(81942)).setValue(6);
        ((ChoiceModelApp) modelBank.getModel(81943)).setValue(6);
        ((ChoiceModelApp) modelBank.getModel(81944)).setValue(6);
        ((ChoiceModelApp) modelBank.getModel(81938)).setValue(6);
        ((RangeModelApp) modelBank.getModel(81444)).setValue(5);
        ((RangeModelApp) modelBank.getModel(81610)).setValue(5);
        ((ChoiceModelApp) modelBank.getModel(82106)).forceUpdate(true);
        NavAsiaApp.getFramework().getSysApp().getChoiceModelApp(1083).setStatus(0);
    }

    private void registerListeners() {
        int[] ids = this.modelBank.getAllModelIds();
        for (int i = 0; i < ids.length; i++) {
            if (ids[i] == 80585 || ids[i] == 82172) {
                continue;
            }
            if (this.modelBank.getModel(ids[i]) instanceof ChoiceModelApp) {
                ((ChoiceModelApp) this.modelBank.getModel(ids[i])).setChoiceListener(this);
            } else if (this.modelBank.getModel(ids[i]) instanceof RangeModelApp) {
                ((RangeModelApp) this.modelBank.getModel(ids[i])).setRangeListener(this);
            } else if (this.modelBank.getModel(ids[i]) instanceof ButtonModelApp) {
                ((ButtonModelApp) this.modelBank.getModel(ids[i])).setButtonListener(this);
            } else if (this.modelBank.getModel(ids[i]) instanceof MatchspellerModelAsiaApp) {
                ((MatchspellerModelAsiaApp) this.modelBank.getModel(ids[i])).setMaxLength(128);
                ((MatchspellerModelAsiaApp) this.modelBank.getModel(ids[i])).setSpellerListener(this);
            } else if (this.modelBank.getModel(ids[i]) instanceof SpellerModelAsiaApp) {
                ((SpellerModelAsiaApp) this.modelBank.getModel(ids[i])).setSpellerListener(this);
            } else {
                if (this.modelBank.getModel(ids[i]) instanceof SpellerModel) {
                    this.log.log(10000, 2457, (long) ids[i]);
                }
                if (this.modelBank.getModel(ids[i]) instanceof TooltipModelApp) {
                    ((TooltipModelApp) this.modelBank.getModel(ids[i])).setListener(this);
                } else if (this.modelBank.getModel(ids[i]) instanceof SlidingListModelApp) {
                    ((SlidingListModelApp) this.modelBank.getModel(ids[i])).setListListener(this);
                } else if (this.modelBank.getModel(ids[i]) instanceof ListModelApp) {
                    ((ListModelApp) this.modelBank.getModel(ids[i])).setListListener(this);
                } else if (this.modelBank.getModel(ids[i]) instanceof VirtualButtonModelApp) {
                    ((VirtualButtonModelApp) this.modelBank.getModel(ids[i])).setVirtualButtonListener(this);
                }
            }
        }
        NavAsiaApp.getFramework().getSysApp().getButtonModelApp(609).setButtonListener(this);
        NavAsiaApp.getFramework().getSysApp().getButtonModelApp(629).setButtonListener(this);
        NavAsiaApp.getFramework().getSysApp().getButtonModelApp(613).setButtonListener(this);
        NavAsiaApp.getFramework().getSysApp().getButtonModelApp(630).setButtonListener(this);
        NavAsiaApp.getFramework().getSysApp().getButtonModelApp(683).setButtonListener(this);
        NavAsiaApp.getFramework().getSysApp().getButtonModelApp(685).setButtonListener(this);
        NavAsiaApp.getFramework().getSysApp().getChoiceModelApp(1047).setChoiceListener(this);
        this.log.log(10000000, 6613);
    }

    public void keyTyped(int id) {
        this.appNavAsia.keyTyped(id, false);
    }

    public void keyReleased(int id) {
    }

    public void keyPressed(int id) {
    }

    public void itemSelected(int id, int index, int arg) {
        int value = index;
        if (id == 80792) {
            ListModelApp list = (ListModelApp) this.modelBank.getModel(id);
            IntegerListCell first = (IntegerListCell) list.getCell(value, 0);
            IntegerListCell second = (IntegerListCell) list.getCell(value, 1);
            if (second.getValue() == 0 && first.getValue() == 8) {
                return;
            }
        }
        if (id == 80803 || id == 80859) {
            if (value == 2 && ((ChoiceModelApp) this.modelBank.getModel(id)).getValue() != 2) {
                ((ChoiceModelApp) this.modelBank.getModel(id)).setValue(2);
                return;
            }
            if (value == 0 && ((ChoiceModelApp) this.modelBank.getModel(id)).getValue() != 0) {
                ((ChoiceModelApp) this.modelBank.getModel(id)).setValue(0);
                return;
            }
            if (value != 1 && value != 0 && value != 5) {
                return;
            }
            if (value == 5) {
                return;
            }
        }
        if (id == 81463) {
            id = 81567;
        }
        if (id == 1047) {
            value = NavAsiaApp.getFramework().getSysApp().getChoiceModelApp(1047).getValue();
            id = 81974;
            this.log.log(10000000, 6614, (long) value);
        }
        if (id == 81524) {
            return;
        }
        this.appNavAsia.itemSelected(id, (long) value);
    }

    public void increment(int id, int steps) {
        if (taken(id, steps)) {
            return;
        }
        this.appNavAsia.increment(id, steps);
    }

    public void decrement(int id, int steps) {
        if (taken(id, -steps)) {
            return;
        }
        this.appNavAsia.decrement(id, steps);
    }

    /* Whatever fails in NavAsiaZoom, even loading it, the stock call runs. */
    private static boolean taken(int id, int steps) {
        try {
            return NavAsiaZoom.step(id, steps);
        } catch (Throwable t) {
            return false;
        }
    }

    public void textChanged(int id, String text, String typed) {
        this.appNavAsia.spellerTextChanged(id, text, typed);
    }

    public void textChanged(int id, String text, String typed, char c) {
        this.appNavAsia.spellerTextChanged(id, text, typed);
    }

    public void textChanged(int id, String text, String typed, int arg) {
        this.appNavAsia.spellerTextChanged(id, text, typed);
    }

    public void textChanged(int id, String text) {
    }

    public void commandPressed(int id, int command) {
    }

    public void textChanged(int id, String text, char c) {
        ((MatchspellerModelAsiaApp) this.modelBank.getModel(id)).setStatus(0);
        this.appNavAsia.matchSpellerTextChanged(id, text, c);
    }

    public void itemReleased(int id, int index, int arg) {
    }

    public void itemFocused(int id, int index, int arg) {
        if (id == 81019 || id == 81071 || id == 80792 || id == 80796 || id == 81360 || id == 80408 || id == 81658
                || id == 81913) {
            this.appNavAsia.itemFocused(id, (long) index);
        }
    }

    public void itemSelected(int id, ListRow row, int arg) {
        this.appNavAsia.itemSelected(id, ((NavAsiaListRow) row).getRowID());
    }

    public void requestRowsAfter(int id, ListRow row, int count) {
        this.appNavAsia.fillListBufferAtEnd(id, ((NavAsiaListRow) row).getRowID(), count);
    }

    public void requestRowsBefore(int id, ListRow row, int count) {
        this.appNavAsia.fillListBufferAtStart(id, ((NavAsiaListRow) row).getRowID(), count);
    }

    public void fastScrolling(int id, byte speed, ListRow row) {
    }

    public void scrollingActive(int id, boolean active) {
    }

    public void itemFocused(int id, ListRow row, int index, int arg) {
        if (id == 81793 || id == 82000) {
            this.appNavAsia.itemFocused(id, ((NavAsiaListRow) row).getRowID());
        }
    }

    public void rebuildListFromEnd(int id) {
    }

    public void rebuildListFromStart(int id) {
    }

    public void stickIdle(int id) {
        this.appNavAsia.itemSelected(id, 2L);
    }

    public void stickN(int id) {
        long value = 3L;
        if (id == 81874) {
            value = 1L;
        }
        this.appNavAsia.itemSelected(id, value);
    }

    public void stickNW(int id) {
        this.appNavAsia.itemSelected(id, 4L);
    }

    public void stickW(int id) {
        this.appNavAsia.itemSelected(id, 5L);
    }

    public void stickSW(int id) {
        this.appNavAsia.itemSelected(id, 6L);
    }

    public void stickS(int id) {
        this.appNavAsia.itemSelected(id, 7L);
    }

    public void stickSE(int id) {
        this.appNavAsia.itemSelected(id, 8L);
    }

    public void stickE(int id) {
        this.appNavAsia.itemSelected(id, 9L);
    }

    public void stickNE(int id) {
        this.appNavAsia.itemSelected(id, 10L);
    }

    public void keyPressed(int id, int arg) {
        this.keyPressed(id);
    }

    public void keyReleased(int id, int arg) {
        this.keyReleased(id);
    }

    public void keyTyped(int id, int arg) {
        this.keyTyped(id);
    }

    public void itemSelected(int id, int index, int arg, int extra) {
        this.itemSelected(id, index, arg);
    }

    public void decrement(int id, int steps, int arg) {
        this.decrement(id, steps);
    }

    public void increment(int id, int steps, int arg) {
        this.increment(id, steps);
    }

    public void textChanged(int id, String text, String typed, char c, int arg) {
        this.textChanged(id, text, c);
    }

    public void commandPressed(int id, int command, int arg) {
        this.commandPressed(id, command);
    }

    public void textChanged(int id, String text, int arg) {
        this.textChanged(id, text);
    }

    public void itemFocused(int id, int index, int arg, int extra) {
        this.itemFocused(id, index, arg);
    }

    public void itemReleased(int id, int index, int arg, int extra) {
        this.itemReleased(id, index, arg);
    }

    public void textChanged(int id, String text, char c, int arg) {
        this.textChanged(id, text, c);
    }

    public void requestRowsAfter(int id, ListRow row, int count, int arg) {
        this.requestRowsAfter(id, row, count);
    }

    public void requestRowsBefore(int id, ListRow row, int count, int arg) {
        this.requestRowsBefore(id, row, count);
    }

    public void fastScrolling(int id, byte speed, ListRow row, int arg) {
        this.fastScrolling(id, speed, row);
    }

    public void rebuildListFromEnd(int id, int arg) {
        this.rebuildListFromEnd(id);
    }

    public void rebuildListFromStart(int id, int arg) {
        this.rebuildListFromStart(id);
    }

    public void scrollingActive(int id, boolean active, int arg) {
        this.scrollingActive(id, active);
    }

    public void stickE(int id, int arg) {
        this.stickE(id);
    }

    public void stickIdle(int id, int arg) {
        this.stickIdle(id);
    }

    public void stickN(int id, int arg) {
        this.stickN(id);
    }

    public void stickNE(int id, int arg) {
        this.stickNE(id);
    }

    public void stickNW(int id, int arg) {
        this.stickNW(id);
    }

    public void stickS(int id, int arg) {
        this.stickS(id);
    }

    public void stickSE(int id, int arg) {
        this.stickSE(id);
    }

    public void stickSW(int id, int arg) {
        this.stickSW(id);
    }

    public void stickW(int id, int arg) {
        this.stickW(id);
    }

    public void keyPressed(int id, int arg, int extra) {
        this.keyPressed(id, extra);
    }

    public void keyReleased(int id, int arg, int extra) {
        this.keyReleased(id, extra);
    }

    public void keyTyped(int id, int key, int arg) {
        if (id == 80831 || id == 80825 || id == 81875) {
            if (key == 15) {
                ((ButtonModelApp) this.modelBank.getModel(id)).setPressed(false);
                return;
            }
            boolean pressed = id == 81875 ? true : !((ButtonModelApp) this.modelBank.getModel(id)).getPressed();
            ((ButtonModelApp) this.modelBank.getModel(id)).setPressed(pressed);
        }
        if (id == 81366) {
            int value = 1;
            if (((ChoiceModelApp) this.modelBank.getModel(81367)).getValue() == 1) {
                value = 0;
            }
            this.itemSelected(81367, value, arg);
            return;
        }
        if (id == 609) {
            id = 81589;
            this.appNavAsia.showInfoScreen(90111, false);
            NavAsiaApp.getFramework().getHMIService().fireSMEvent(0, 1819);
        }
        if (id == 629) {
            id = 81588;
            NavAsiaApp.getFramework().getSysApp().getChoiceModelApp(608).setValue(0);
        }
        if (id == 613) {
            id = 81591;
        }
        if (id == 630) {
            id = 81590;
            NavAsiaApp.getFramework().getSysApp().getChoiceModelApp(612).setValue(0);
        }
        if (id == 685) {
            id = 81624;
        }
        if (id == 683) {
            id = 81622;
            NavAsiaApp.getFramework().getSysApp().getChoiceModelApp(684).setValue(0);
        }
        this.keyTyped(id, arg);
    }

    public void touchPadPositionMoved(int id, int x0, int y0, int x1, int y1, int arg) {
        if (NavAsiaApp.getFramework().isVW()) {
            this.appNavAsia.touchScreenMoved(id, x0, y0, x1, y1);
        } else {
            this.appNavAsia.touchPadMovement(id, x1 - x0, y1 - y0);
        }
    }

    public void nonAlphaNumTPCharsChanged(int id, int arg, String chars) {
        ((MatchspellerModelAsiaApp) this.modelBank.getModel(id)).setStatus(0);
        this.appNavAsia.validateCharacters(id, chars);
    }

    public void inputModeTPChanged(int id, int mode, int arg) {
        ((MatchspellerModelAsiaApp) this.modelBank.getModel(id)).setStatus(0);
        this.appNavAsia.inputModeChanged(id, mode);
    }

    public void getValidHanziCharsWindow(int id, int a, int b, int arg) {
        ((MatchspellerModelAsiaApp) this.modelBank.getModel(id)).setStatus(0);
        this.appNavAsia.getValidHanziCharsWindow(id, a, b);
    }

    public void addSpellerStroke(int id, String a, String b, int arg) {
        ((MatchspellerModelAsiaApp) this.modelBank.getModel(id)).setStatus(0);
        this.appNavAsia.addSpellerStroke(id, a, b);
    }

    public void cancelTimer(Timer timer) {
    }

    public void fireTimer(Timer timer) {
    }

    public void tooltipDataRequested(int id, int a, int b, boolean c, int arg) {
    }

    public void tooltipDataRequested(int id, int a, ListRow row, boolean c, int arg) {
    }

    public void tooltipHidden(int id, int a, int arg) {
    }

    public void tooltipVisible(int id, int a, int arg) {
    }

    public void runningOutOfData(int id, ListRow row, int a, int arg) {
    }
}
