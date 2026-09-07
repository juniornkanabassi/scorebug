// Plain property inspector boilerplate, no framework. Stream Deck calls connectElgatoStreamDeckSocket with
// the websocket port and this action instance's uuid; every element with [data-setting] is read on change
// and round-tripped through getSettings/setSettings so a reopened inspector shows the saved values.
let websocket = null;
let uuid = null;

function connectElgatoStreamDeckSocket(inPort, inUUID, inRegisterEvent, inInfo, inActionInfo) {
	uuid = inUUID;
	websocket = new WebSocket("ws://127.0.0.1:" + inPort);
	websocket.onopen = () => {
		websocket.send(JSON.stringify({ event: inRegisterEvent, uuid: inUUID }));
		const info = JSON.parse(inActionInfo);
		applySettings(info.payload && info.payload.settings ? info.payload.settings : {});
	};
	websocket.onmessage = (evt) => {
		const msg = JSON.parse(evt.data);
		if (msg.event === "didReceiveSettings") applySettings(msg.payload.settings || {});
	};
}

function applySettings(settings) {
	document.querySelectorAll("[data-setting]").forEach((el) => {
		const value = settings[el.dataset.setting];
		if (value === undefined) return;
		if (el.type === "checkbox") el.checked = !!value;
		else el.value = value;
	});
}

function saveSettings() {
	const settings = {};
	document.querySelectorAll("[data-setting]").forEach((el) => {
		const key = el.dataset.setting;
		let value = el.type === "checkbox" ? el.checked : el.value;
		if (el.dataset.numeric) value = value === "" ? undefined : Number(value);
		if (value !== undefined && value !== "") settings[key] = value;
	});
	websocket.send(JSON.stringify({ event: "setSettings", context: uuid, payload: settings }));
}

document.addEventListener("change", (e) => {
	if (e.target.matches("[data-setting]")) saveSettings();
});
