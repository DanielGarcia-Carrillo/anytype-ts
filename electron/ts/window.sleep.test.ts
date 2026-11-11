import { EventEmitter } from 'events';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
	ipc: null as any,
	config: {} as Record<string, any>,
	// When false, a tab ignores close-session and closeTabSession falls back to its timeout
	answerCloseSession: true,
}));

vi.mock('electron', async () => {
	const { EventEmitter } = await import('events');
	mocks.ipc = new EventEmitter();

	class FakeWebContents {
		id = Math.random();
		tabId = '';
		destroyed = false;
		loading = false;
		audible = false;
		devTools = false;
		handlers: Record<string, (...args: any[]) => void> = {};
		send = vi.fn((channel: string) => {
			if ((channel == 'close-session') && mocks.answerCloseSession) {
				queueMicrotask(() => mocks.ipc.emit('tab-session-closed', {}, this.tabId));
			};
		});
		on (event: string, cb: (...args: any[]) => void) {
			this.handlers[event] = cb;
		};
		setWindowOpenHandler () {};
		isDestroyed () {
			return this.destroyed;
		};
		close = vi.fn(() => {
			this.destroyed = true;
		});
		loadURL = vi.fn(() => {
			this.loading = true;
		});
		isLoading () {
			return this.loading;
		};
		isCurrentlyAudible () {
			return this.audible;
		};
		isDevToolsOpened () {
			return this.devTools;
		};
		focus () {};
		setZoomLevel () {};
		reload () {};
		finishLoad () {
			this.loading = false;
			this.handlers['did-finish-load']?.();
		};
	};

	class WebContentsView {
		webContents: FakeWebContents;
		constructor (opts: any) {
			this.webContents = new FakeWebContents();
			const arg = (opts.webPreferences.additionalArguments || []).find((it: string) => it.startsWith('--tab-id='));
			this.webContents.tabId = arg ? arg.replace('--tab-id=', '') : '';
		};
		setBackgroundColor () {};
		setBounds () {};
	};

	return {
		app: { getPath: () => '/tmp', getVersion: () => '0.0.0', on: () => {} },
		BrowserWindow: class {},
		WebContentsView,
		nativeImage: {},
		dialog: {},
		ipcMain: mocks.ipc,
	};
});

vi.mock('electron-util', () => ({ is: { development: false, windows: false, linux: false, macos: true }, fixPathForAsarUnpack: (p: string) => p }));
vi.mock('electron-window-state', () => ({ default: () => ({}) }));
vi.mock('@electron/remote/main', () => ({ enable: () => {} }));
vi.mock('./api', () => ({ default: { hasPinSet: false, isPinChecked: true } }));
vi.mock('./config', () => ({ default: { config: mocks.config } }));
vi.mock('./update', () => ({ default: {} }));
vi.mock('./menu', () => ({ default: {} }));
vi.mock('./safeStorage', () => ({ getSafeStorage: () => ({ get: () => undefined, set: () => {} }) }));
vi.mock('./lib/trustedUrl', () => ({ isExternalUrlAllowed: () => false }));
vi.mock('./util', () => {
	const getView = (win: any, id: string) => win?.views?.find((v: any) => v.id == id);
	return {
		default: {
			getPort: () => '0',
			getTheme: () => 'light',
			getBgColor: () => '#fff',
			electronPath: () => '/app/electron',
			appPath: '/app',
			log: () => {},
			send: () => {},
			sendToTab: () => {},
			sendToAllTabs: () => {},
			getView,
			getActiveView: (win: any) => getView(win, win?.activeTabId),
		},
	};
});

import WindowManager from './window';

const MINUTE = 60 * 1000;

const makeWindow = (): any => {
	const children = new Set<any>();
	return {
		id: 1,
		views: [],
		activeTabId: '',
		isQuickSearch: false,
		isDestroyed: () => false,
		getContentBounds: () => ({ x: 0, y: 0, width: 800, height: 600 }),
		webContents: { send: vi.fn() },
		contentView: {
			children,
			addChildView: (v: any) => children.add(v),
			removeChildView: (v: any) => children.delete(v),
		},
	};
};

// Two loaded tabs, the second one active
const setup = () => {
	const win = makeWindow();
	const first = WindowManager.createTab(win, { route: '/main/page/a' }, { setActive: true }) as any;
	first.webContents.finishLoad();
	first.data.token = 'old-token';

	const second = WindowManager.createTab(win, { route: '/main/page/b' }, { setActive: true }) as any;
	second.webContents.finishLoad();

	return { win, first, second };
};

describe('WindowManager tab sleep', () => {

	beforeEach(() => {
		vi.useFakeTimers();
		mocks.answerCloseSession = true;
		for (const key of Object.keys(mocks.config)) {
			delete mocks.config[key];
		};
	});

	afterEach(() => {
		WindowManager.sleepTimers.forEach(t => clearTimeout(t));
		WindowManager.sleepTimers.clear();
		mocks.ipc.removeAllListeners();
		vi.useRealTimers();
	});

	test('an inactive tab sleeps after the default delay and keeps its id and route', async () => {
		const { win, first } = setup();
		const oldWebContents = first.webContents;

		await vi.advanceTimersByTimeAsync(14 * MINUTE);
		expect(oldWebContents.send).not.toHaveBeenCalledWith('close-session');

		await vi.advanceTimersByTimeAsync(1 * MINUTE);

		expect(oldWebContents.send).toHaveBeenCalledWith('close-session');
		expect(oldWebContents.close).toHaveBeenCalled();

		const fresh = win.views[0];
		expect(fresh).not.toBe(first);
		expect(fresh.id).toBe(first.id);
		expect(fresh.isLoaded).toBe(false);
		expect(fresh.data.route).toBe('/main/page/a');
		expect(fresh.data.token).toBeUndefined();
		expect(fresh.webContents.loadURL).not.toHaveBeenCalled();
	});

	test('activating a sleeping tab loads it again', async () => {
		const { win, first } = setup();

		await vi.advanceTimersByTimeAsync(15 * MINUTE);
		const fresh = win.views[0];

		WindowManager.setActiveTab(win, first.id);

		expect(win.contentView.children.has(fresh)).toBe(true);
		expect(fresh.webContents.loadURL).toHaveBeenCalledTimes(1);
	});

	test('the active tab never sleeps, and switching back cancels the timer', async () => {
		const { win, first, second } = setup();

		await vi.advanceTimersByTimeAsync(10 * MINUTE);
		WindowManager.setActiveTab(win, first.id);
		await vi.advanceTimersByTimeAsync(60 * MINUTE);

		// first is active and untouched; second has been inactive for 60 minutes and sleeps
		expect(win.views[0]).toBe(first);
		expect(first.webContents.close).not.toHaveBeenCalled();
		expect(win.views[1]).not.toBe(second);
		expect(second.webContents.close).toHaveBeenCalled();
	});

	test('a delay of 0 turns sleeping off', async () => {
		mocks.config.tabSleepMinutes = 0;
		const { win, first } = setup();

		await vi.advanceTimersByTimeAsync(24 * 60 * MINUTE);

		expect(win.views[0]).toBe(first);
		expect(first.webContents.send).not.toHaveBeenCalledWith('close-session');
	});

	test('the delay follows the setting', async () => {
		mocks.config.tabSleepMinutes = 5;
		const { win, first } = setup();

		await vi.advanceTimersByTimeAsync(5 * MINUTE);

		expect(win.views[0]).not.toBe(first);
	});

	test('a tab playing sound stays awake and is checked again later', async () => {
		const { win, first } = setup();
		first.webContents.audible = true;

		await vi.advanceTimersByTimeAsync(15 * MINUTE);
		expect(win.views[0]).toBe(first);

		first.webContents.audible = false;
		await vi.advanceTimersByTimeAsync(15 * MINUTE);
		expect(win.views[0]).not.toBe(first);
	});

	test('a tab activated while its session closes shows the fresh view', async () => {
		mocks.answerCloseSession = false;
		const { win, first } = setup();

		await vi.advanceTimersByTimeAsync(15 * MINUTE);
		expect(first.webContents.send).toHaveBeenCalledWith('close-session');

		// The user clicks the tab before the session close finishes
		WindowManager.setActiveTab(win, first.id);
		await vi.advanceTimersByTimeAsync(5000);

		const fresh = win.views[0];
		expect(fresh).not.toBe(first);
		expect(win.activeTabId).toBe(first.id);
		expect(win.contentView.children.has(first)).toBe(false);
		expect(win.contentView.children.has(fresh)).toBe(true);
		expect(fresh.webContents.loadURL).toHaveBeenCalledTimes(1);
	});

	test('a tab closed while its session closes is not brought back', async () => {
		mocks.answerCloseSession = false;
		const { win, first } = setup();

		await vi.advanceTimersByTimeAsync(15 * MINUTE);
		WindowManager.removeTab(win, first.id, false);
		await vi.advanceTimersByTimeAsync(5000);

		expect(win.views.map((it: any) => it.id)).not.toContain(first.id);
		expect(win.views).toHaveLength(1);
	});

	test('a tab opened in the background sleeps once loaded', async () => {
		const { win } = setup();
		const background = WindowManager.createTab(win, { route: '/main/page/c' }, { setActive: false }) as any;

		// Still loading when the timer fires: checked again later
		await vi.advanceTimersByTimeAsync(15 * MINUTE);
		expect(win.views[2]).toBe(background);

		background.webContents.finishLoad();
		await vi.advanceTimersByTimeAsync(15 * MINUTE);
		expect(win.views[2]).not.toBe(background);
		expect(win.views[2].id).toBe(background.id);
	});

	test('a tab restored at startup and never opened is left alone', async () => {
		const { win } = setup();
		const deferred = WindowManager.createTab(win, { route: '/main/page/d' }, { setActive: false, deferLoad: true }) as any;

		await vi.advanceTimersByTimeAsync(60 * MINUTE);

		expect(win.views[2]).toBe(deferred);
		expect(deferred.webContents.send).not.toHaveBeenCalledWith('close-session');
	});
});
