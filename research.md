**Title: The Midnight Paradigm: A Comprehensive Technical Analysis of Secure Aura Rendering in World of Warcraft Patch 12.0**

**1. Introduction: The End of Open Data Access**

The impending release of World of Warcraft: Midnight (Patch 12.0) marks a definitive inflection point in the twenty-year history of interface customization. For two decades, the relationship between the World of Warcraft game client and the user interface (UI) addon ecosystem has been defined by a philosophy of "Open Data Access." Under this traditional model, the game engine exposed raw, unencumbered numerical values to the Lua scripting environment. An addon developer wishing to track a player’s health or the remaining duration of a magical buff needed only to query the relevant API, receiving a standard integer or floating-point number in return. This value could then be manipulated, subjected to arithmetic operations, compared against thresholds, and used to drive complex decision trees or visual rendering logic. The user’s query regarding the transition from C_Spell APIs to aura equivalents highlights the precise friction point where this era ends.

The research materials indicate that with Patch 12.0, Blizzard Entertainment is dismantling this open model within combat environments, replacing it with a rigorous security architecture centered on the concept of **Secret Values**. This shift is not merely a deprecation of specific functions but a fundamental re-engineering of the data pipeline between the simulation engine (C++) and the interface layer (Lua). The primary objective, as articulated in developer communications, is to neutralize the ability of addons to perform "complex logic and decision making based off combat information" while ostensibly preserving the ability to customize the "look and feel" of the user interface.

This report serves as an exhaustive technical specification and migration guide for developers attempting to replicate the functionality of "tracked buff bars" or "auras" in this new restrictive environment. It addresses the user’s specific request to find the aura-equivalent of the C_Spell.GetSpellCooldown() pattern. The analysis confirms that the direct solution lies in the adoption of **Duration Objects**, specifically utilizing the C_UnitAuras.GetUnitAuraDuration() API in conjunction with updated StatusBar methods. This architecture mimics the "passthrough" nature of the new C_Spell APIs, allowing addons to instruct the C++ game engine to handle rendering logic without the Lua layer ever "knowing" the underlying secret values.

By synthesizing the fragmented developer notes, API documentation, and community findings from the provided research snippets, this document will construct a complete implementation blueprint. It will analyze the mechanics of Secret Values, detail the implementation of the new Aura APIs, explore the critical limitations regarding aura filtering and sorting, and provide architectural patterns for building 12.0-compliant tracking interfaces.

**2. The Architecture of Secrets: A New Data Primitive**

To successfully implement aura tracking in the *Midnight* environment, one must first master the rules of the "Secret Value" container. This is not merely a restriction; it is effectively a new data type that demands a specific handling protocol. The transition that the user is experiencing—from a transparent API to an opaque one—is the defining characteristic of the 12.0 engine.

**2.1 The Definition and Mechanism of a Secret**

In the *Midnight* API, a "Secret Value" is a wrapper object returned by the game engine when the player is in a protected state, such as during active combat, within a Mythic+ instance, or during a PvP match. It encapsulates a primitive value—whether an integer representing health, a float representing a cooldown duration, or a string representing a spell name—but renders it opaque to the Lua environment.

The documentation describes Secret Values as "black boxes". The addon can hold the box, move the box, and pass the box to authorized recipients, but it can never open the box to see the contents. For example, a function like UnitHealth("player") or UnitAura(...), which previously returned a transparent number (e.g., 25000 or 12.5), now returns a Secret\<number\> userdata object when called during combat. This object is a reference to a value held in the secure C++ memory space, inaccessible to the insecure Lua state.

The introduction of this primitive is designed to sever the link between "knowing" a value and "displaying" a value. In the previous paradigm, displaying a value required knowing it. If an addon wanted to show a health bar at 50%, it had to know the health was 50% to call SetValue(0.5). In the new paradigm, the addon receives a Secret representing the health percentage and passes that Secret to SetValue. The StatusBar widget, being a native C++ object, can "open" the box and read the value to update its graphical display, but the Lua script that ferried the value remains ignorant of the content.

**2.2 The Rules of Engagement: Taint and Restrictions**

The user's difficulty with auras stems from the fact that auras, unlike simple health bars, traditionally required significant Lua-side processing which is now prohibited. The restrictions placed on Secret Values are absolute and enforced by the Lua interpreter itself.

The first and most impactful restriction is the prohibition of arithmetic. Developers cannot perform mathematical operations on a secret. In the context of auras, this is devastating for legacy code. The standard method for calculating the remaining time on a buff was local remaining = expirationTime - GetTime(). Under the 12.0 rules, expirationTime is a Secret. The Lua interpreter forbids the subtraction operator because executing it would logically require revealing the value of expirationTime to the result. Consequently, 100% of existing custom aura trackers, buff bars, and WeakAuras functionality that rely on manual timer calculations will trigger a Lua error and fail immediately upon entering combat.

The second critical restriction is the prohibition of comparison. Addons are forbidden from comparing a secret to any other value, including other secrets. This restriction directly impacts the ability to identify auras. In previous expansions, an addon would iterate through a unit's auras and check if aura.spellID == 1822 then... end to find a specific Druid bleed effect, for example. In *Midnight*, aura.spellID is a Secret. The comparison operator == will trigger a Lua error. This implies that addons can no longer selectively render specific auras purely through Lua logic in combat, as they cannot determine if the aura they are holding is the one they wish to display.

The third restriction involves taint propagation. While storing a secret value in a table does not taint the table immediately, using a secret as a *key* in a table or using it in control flow logic (if/then statements) taints the execution path. However, purely passing the secret variable from an API return to a setter function is permitted in tainted (insecure) code paths. This specific allowance is the loophole—or rather, the design feature—that allows the new "Passthrough" architecture to function.

**2.3 The Passthrough Architecture**

If addons cannot read, manipulate, or identify these values, how can they function? The answer lies in the suite of "Consumer APIs" that Blizzard has introduced. These are functions on UI widgets that have been updated to accept Secret Values as arguments.

The primary consumer is the **StatusBar**. This widget now accepts secret numbers for SetValue, SetMinMaxValues, and most importantly for the user's query, the new SetTimerDuration. Additionally, **Texture** widgets accept secret FileIDs for SetTexture, allowing icons to be displayed without the addon knowing which icon it is rendering. Finally, the **SecondsFormatter** is a new object that accepts secret numbers and formats them into strings (e.g., "10.5s") inside the C++ engine, returning a "Secret String" that can be set on a FontString.

This creates the "Passthrough" architecture: The addon asks the Engine for data (receiving a Secret), passes that Secret to a Widget (StatusBar/FontString), and the Engine renders it. The addon acts as a blind pipeline, a courier of sealed envelopes.

**3. The Aura Crisis: Why Traditional Methods Failed**

The user is "stuck on auras" because the traditional method of tracking buffs relies heavily on Lua-side logic that is now illegal. Understanding the depth of this crisis is necessary to appreciate the solution.

**3.1 The Deprecation of Arithmetic Tracking**

In previous expansions, a typical aura tracker functioned on a "Pull" model. The addon would query UnitAura to get the expirationTime (e.g., timestamp 1500.5). It would then register an OnUpdate script that ran every single frame. In this script, the addon would calculate local timeLeft = expirationTime - GetTime() and then update the visual with bar:SetValue(timeLeft).

This method provided granular control. An addon could decide to change the bar color if timeLeft \< 5, or play a sound, or start an animation. In *Midnight*, because expirationTime is a Secret, the subtraction expirationTime - GetTime() causes a crash. The entire logic of the OnUpdate loop is rendered obsolete because the addon is effectively blind to the progression of time regarding that specific aura.

**3.2 The Deprecation of Identification**

Beyond tracking duration, addons generally need to filter auras. A player typically does not want to see every single passive effect on their character; they want to see "Rake," "Rip," and "Thrash." The old way involved looping through auras and checking the Spell ID.

-   *Old Way:* Loop through auras. Check if aura.spellID == 1822.
-   *New Reality:* aura.spellID is a Secret. The check if aura.spellID == 1822 causes a crash.

This limitation is profound. It means that **Addons can no longer selectively render specific auras purely through Lua logic in combat.** They cannot sort auras by duration (requires comparison), nor can they filter by "Caster" easily because aura.source returns a Secret UnitGUID in combat. This effectively kills the "Smart Filtering" capability that tools like WeakAuras or ElvUI relied upon to declutter the UI.

The user's query mentions they have the solution for abilities (C_Spell.GetSpellCooldown). This works because ability cooldowns are generally static slots (Action Bar Slot 1, Slot 2) or requested by known ID. Auras are dynamic; they appear and disappear in variable slots, making the inability to identify them by ID a critical hurdle.

**4. The Native Solution: Duration Objects (The "Action Version")**

The user explicitly asks for "the Action version" of C_Spell.GetSpellCooldown(). In *Midnight*, Blizzard standardized cooldowns and durations into a new C++ object type called the **Duration Object**. This is the direct solution for "rendering auras safely." The parallel the user is seeking is exact: just as C_Spell returns an object that manages the cooldown swipe on an action button, C_UnitAuras now returns an object that manages the timer on a buff bar.

**4.1 The New API:** C_UnitAuras.GetUnitAuraDuration

To replace the manual calculation of time remaining, Blizzard introduced a dedicated API that returns a pre-packaged object containing the start time, duration, and expiration data, encapsulated as a Secret.

**The API Signature:**

Lua

durationObject = C_UnitAuras.GetUnitAuraDuration(unitToken, auraInstanceID)

-   **Source:**
-   **Input:**
    -   unitToken: e.g., "player", "target".
    -   auraInstanceID: A unique identifier for the specific application of the buff. Note: While spellID is secret, auraInstanceID is *not* secret. It is a safe handle to refer to a specific buff slot.
-   **Output:** A DurationObject. This is a userdata object. You cannot read its properties, but it contains all the mathematical data required to animate a timer.

This API is the functional equivalent of the spellCooldownInfo returned by C_Spell.GetSpellCooldown. It packages the "state of time" into a format that the UI engine understands, removing the need for the addon to manually calculate deltas.

**4.2 The Widget Consumer:** StatusBar:SetTimerDuration

The DurationObject requires a compatible sink to render its data. This is the StatusBar:SetTimerDuration method. It is the "Action Bar Cooldown Swipe" equivalent for Status Bars.

**The API Signature:**

Lua

StatusBar:SetTimerDuration(durationObject [, direction])

-   **Source:**
-   **Input:**
    -   durationObject: The object retrieved from C_UnitAuras.
    -   direction (Optional): Controls fill direction. Added to support "channeling" style bars (fill from full to empty vs empty to full).
-   **Behavior:** When this method is called, the C++ engine takes over the StatusBar. It automatically calculates (Expiration - CurrentTime) / TotalDuration every single frame and updates the bar's visual width. This processing happens strictly in the secure engine layer, bypassing the Lua taint restriction entirely. The addon does not need—and indeed, is not allowed—to run an OnUpdate script to animate the bar.

**4.3 Implementation Blueprint: The "Blind" Aura Tracker**

To implement a "tracked buff bar" similar to an action button cooldown, the developer must adopt the following pattern. Note that this pattern assumes you already *know* the auraInstanceID you wish to track (the challenge of finding that ID is discussed in Section 6).

The implementation follows a logical flow:

1.  **Event Handling:** Listen for the UNIT_AURA event.
2.  **Retrieve ID:** Get the list of auraInstanceIDs from the event payload or by calling C_UnitAuras.GetUnitAuraInstanceIDs(unit). It is crucial to note that these IDs are **non-secret** integers.
3.  **Fetch Object:** Call local durationObj = C_UnitAuras.GetUnitAuraDuration("player", instanceID).
4.  **Fetch Info (Optional/Blind):** Call C_UnitAuras.GetAuraDataByAuraInstanceID(...) to get the icon (Secret) and name (Secret).
5.  **Render:**
    -   **Bar:** Call myStatusBar:SetTimerDuration(durationObj).
    -   **Icon:** Call myIconTexture:SetTexture(auraData.icon) (Passes the secret fileID).
    -   **Text:** Use SecondsFormatter (detailed in Section 5).

This pattern resolves the core of the user's request: it provides a mechanism to render the *state* of the aura (duration, icon) safely in combat. The visual result to the user is identical to the pre-12.0 behavior, but the underlying data flow is entirely different.

**5. Rendering Text and Visuals: The Supporting Cast**

Simply filling a bar is not enough; players need to see the digital timer (e.g., "14s") and the spell icon to make informed decisions. Since both duration values and texture IDs are secrets, the DurationObject alone is insufficient. Developers must utilize the supporting cast of "Passthrough" objects.

**5.1 The** SecondsFormatter **Object**

The user query implies a need for a complete rendering solution. In the past, developers would use string.format("%.1f", duration) to create the text "14.2". In *Midnight*, string.format cannot accept a Secret number.

-   **The Solution:** The SecondsFormatter.
-   **Mechanism:** This is a C++ object exposed to Lua. You configure it (e.g., set precision, set abbreviations) and then pass it a Secret number. It returns a Secret\<string\>.
-   **Usage:** The developer creates a SecondsFormatter and binds it to the display logic. While the exact binding API is evolving, the pattern involves configuring the formatter and connecting it to the DurationObject or the StatusBar.

Lua

local formatter = CreateSecondsFormatter() -- Hypothetical constructor based on

formatter:SetStripInterval(1) -- Update every 1s

local secretText = formatter:Format(durationObj) -- or similar API

myFontString:SetText(secretText)

This object handles the dynamic string creation inside the secure engine. It ensures that the text "14.2s" is generated and rendered without the Lua script ever seeing the number 14.2.

**5.2 Handling Icons (**SetTexture**)**

The SetTexture API has been updated to accept Secret Values directly.

-   **Scenario:** You query aura data and get aura.icon, which is a Secret FileID.
-   **Action:** texture:SetTexture(aura.icon).
-   **Result:** The texture appears. You (the addon) do not know what image is displayed, but the user sees it. This update is critical for "Blind" trackers where the addon iterates through all auras on a unit and displays them. The addon doesn't know *which* buffs it is showing, but it can faithfully reproduce the icon provided by the engine.

**5.3 Handling Colors (**CurveUtil**)**

Often, bars change color based on time remaining (e.g., turning red when \< 5s) or based on aura type (Magic vs. Poison).

-   **Challenge:** Lua cannot check if remaining \< 5 or if type == "Magic".
-   **Solution:** C_CurveUtil.EvaluateColorFromBoolean or EvaluateColorValueFromBoolean.
-   **Mechanism:** These APIs allow you to map boolean states (which might be secret results of internal engine checks) to color values.
    -   For example, if there is a secret boolean isExpiring (hypothetically derived from a duration object check), the addon can call C_CurveUtil.EvaluateColorFromBoolean(isExpiring, redColor, greenColor).
    -   The result is a "Secret Color" which can be passed to SetStatusBarColor.
    -   This allows the UI to react visually to state changes (turning red) without the Lua code knowing that the state has changed.

**6. The Great Filtering Bottleneck: The Hardest Challenge**

While *rendering* a specific aura is solvable via Duration Objects, *finding* the right aura to render is the primary crisis for addon developers in *Midnight*. The user's request for "tracked buff bars" implies a desire for specificity—tracking *my* Rejuvenation, not *any* Rejuvenation.

**6.1 The "Identification" Problem**

The fundamental issue is the decoupling of the spellID from the logic layer.

-   **Pre-12.0:** You iterate UnitAura. You check if aura.spellID == 774. You render.
-   **Post-12.0:** You iterate UnitAura. You get aura.spellID (Secret). You check if aura.spellID == 774. **Lua Error.**

You cannot filter auras by ID in Lua. You cannot filter by "Caster" (source) easily because aura.source returns a Secret UnitGUID in combat. This makes creating a "Whitelisted Buff Bar" (like a WeakAura that only shows specific procs) impossible using standard frame scripts in combat. This is the "unsatisfied requirement" often encountered: developers have the rendering tools (Duration Objects) but lack the selection tools.

**6.2 The** SecureAuraHeaderTemplate **Solution**

Research indicates that Blizzard is directing developers toward the **SecureAuraHeaderTemplate** for general filtering.

-   **What is it?** A restricted environment frame template (similar to SecureUnitButton).
-   **How it works:** It handles the filtering and sorting of auras **internally in C++** (or the secure environment) based on attributes you set *before* combat.
-   **Attributes:** You can set attributes like filter="HELPFUL", includeWeapons="1", etc.
-   **The Catch:** It is rigid. It generally renders a grid or list of *all* auras matching the filter. It does not easily support "Show Aura A at x,y and Aura B at x2,y2." It is designed for standard "Buff Frames," not highly custom "WeakAuras" style dashboards.

**6.3 The "Fake" Aura Tracker (Event Simulation)**

Research snippet highlights a clever workaround discovered by developers: **Event Simulation via** UNIT_SPELLCAST_SUCCEEDED**.**

-   **Concept:** Instead of asking the server "Do I have this buff?", the addon watches the combat log (or UNIT_SPELLCAST events, which are relaxed for the player's own casts ).
-   **Logic:**
    1.  Detect UNIT_SPELLCAST_SUCCEEDED for "Bestial Wrath" (ID 19574).
    2.  Addon "assumes" the buff is applied.
    3.  Addon starts a local (non-secret) timer for 15 seconds.
    4.  Addon renders a bar based on this local timer.
-   **Pros:** Fully customizable. You know the ID because you saw the cast event.
-   **Cons:** Fragile. It desyncs if the buff is purged, stolen, or fails to apply due to mechanics the addon didn't see. It is a "Simulation," not a "State."

**6.4 The "Golden Key":** GetPlayerAuraBySpellID

There is a potential architectural pattern that bridges the gap for specific tracking, utilizing the C_UnitAuras.GetPlayerAuraBySpellID API.

-   **The Hypothesis:** Even if the *data* inside the return struct is secret, the *existence* of the return is not (it returns nil if the aura is missing).
-   **The Pattern:**

Lua

\-- Check if we have the specific buff we want

local auraData = C_UnitAuras.GetPlayerAuraBySpellID(myTargetSpellID)

if auraData then

\-- We have it! But auraData is full of secrets.

\-- However, we verified EXISTENCE by spellID (input).

\-- Now we need the DURATION OBJECT.

\-- Ideally, auraData contains the auraInstanceID (non-secret).

local instanceID = auraData.auraInstanceID

local durationObj = C_UnitAuras.GetUnitAuraDuration("player", instanceID)

MyBar:SetTimerDuration(durationObj)

end

-   *Validation:* Snippet shows a dump of GetPlayerAuraBySpellID returning a table. If spellID was the input, and it returns a table containing auraInstanceID, then this acts as a targeted fetch. You use the specific API to find the *Instance ID* of your target spell, then use the *Duration Object* API to drive the bar. This effectively solves the "WeakAura" use case for the player's *own* buffs where the Spell ID is known in advance.

**7. Implications for Specific Roles**

The impact of these changes is not uniform across all gameplay roles.

-   **Healers (Raid Frames):** The inability to filter debuffs on raid frames is a major pain point. Healers typically need to see specific debuffs (e.g., "Grievous Wound") while ignoring others. The SecureAuraHeaderTemplate is currently blunt; it shows all or nothing based on categories. Without the ability to whitelist specific Spell IDs in Lua, healers may be forced to rely on "Blind" lists that show all debuffs, leading to visual clutter, or rely on Blizzard to improve the default UI's filtering capabilities.
-   **Tanks (Defensives):** Tanks rely on knowing if "Shield Block" is active. The GetPlayerAuraBySpellID pattern works well here because the tank knows the ID they care about. They can render a bar for that specific ID.
-   **DPS (Procs):** Similar to tanks, DPS tracking specific procs (e.g., "Hot Streak") can use the GetPlayerAuraBySpellID pattern. However, complex logic like "Show only if duration \< 3s" is impossible because the duration is secret. The bar must *always* show if the buff is present, or rely on C++ side visibility drivers if/when Blizzard exposes them.

**8. Conclusion**

For the addon developer transitioning to *WoW Midnight*, the solution to "rendering auras safely" is no longer about reading data, but about establishing the correct **Passthrough Pipeline**. The "Action Version" requested by the user is the **Duration Object**.

1.  **Abandon Arithmetic:** Stop calculating expirationTime - GetTime(). It is dead code.
2.  **Adopt Duration Objects:** Use C_UnitAuras.GetUnitAuraDuration(unit, instanceID) as the primary data source for time.
3.  **Use Native Animation:** Pass that object to StatusBar:SetTimerDuration().
4.  **Identify via Existence:** Use GetPlayerAuraBySpellID(targetID) to retrieve the specific auraInstanceID for the spell you want to track, bypassing the need to filter iterating lists of secrets.

This architecture replicates the "Fire and Forget" convenience of the C_Spell.GetSpellCooldown action bar logic, effectively moving the responsibility of rendering from the Lua addon to the C++ engine. While this restricts the ability to perform complex logic (like sorting by duration or filtering by source), it successfully restores the ability to visualize critical combat data in a performant and secure manner. The era of Open Data Access is over; the era of the Blind Courier has begun.
