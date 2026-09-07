// Plugin entry. One WebSocket to ws://127.0.0.1:8600/ws (see src/lib/scorebug.ts), registers every action.
import streamDeck from "@elgato/streamdeck";

import { AddedTime } from "./actions/added-time.js";
import { EndPeriod } from "./actions/end-period.js";
import { Goal } from "./actions/goal.js";
import { Kick } from "./actions/kick.js";
import { PlayPause } from "./actions/play-pause.js";
import { ResetMatch } from "./actions/reset-match.js";
import { SetCompetition } from "./actions/set-competition.js";
import { StartPeriod } from "./actions/start-period.js";
import { StartShootout } from "./actions/start-shootout.js";
import { SwapTeams } from "./actions/swap-teams.js";
import { ToggleBug } from "./actions/toggle-bug.js";
import { ToggleScorers } from "./actions/toggle-scorers.js";
import { UndoKick } from "./actions/undo-kick.js";

streamDeck.logger.setLevel("info");

streamDeck.actions.registerAction(new Goal());
streamDeck.actions.registerAction(new PlayPause());
streamDeck.actions.registerAction(new StartPeriod());
streamDeck.actions.registerAction(new EndPeriod());
streamDeck.actions.registerAction(new AddedTime());
streamDeck.actions.registerAction(new ToggleBug());
streamDeck.actions.registerAction(new ToggleScorers());
streamDeck.actions.registerAction(new StartShootout());
streamDeck.actions.registerAction(new Kick());
streamDeck.actions.registerAction(new UndoKick());
streamDeck.actions.registerAction(new SwapTeams());
streamDeck.actions.registerAction(new ResetMatch());
streamDeck.actions.registerAction(new SetCompetition());

streamDeck.connect();
