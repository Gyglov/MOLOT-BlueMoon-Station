GLOBAL_VAR(current_date_string)

#define AUT_ACCLST 1
#define AUT_ACCINF 2
#define AUT_ACCNEW 3

/obj/machinery/computer/account_database
	name = "Accounts Uplink Terminal"
	desc = "Access transaction logs, account data and all kinds of other financial records."
	icon_screen = "accounts"
	req_access = list(ACCESS_HOP, ACCESS_CAPTAIN, ACCESS_CENT_GENERAL)
	light_color = LIGHT_COLOR_GREEN
	var/receipt_num
	var/machine_id = ""
	var/datum/bank_account/detailed_account_view
	var/activated = TRUE
	var/const/fund_cap = 1000000
	/// Current UI page
	var/current_page = AUT_ACCLST
	/// Next time a print can be made
	var/next_print = 0

/obj/machinery/computer/account_database/New()
	// Why the fuck are these not in a subsystem? They are global variables for fucks sake
	// If someone ever makes a map without one of these consoles, the entire eco AND date system breaks
	// This upsets me a lot
	// AA Todo: SSeconomy
	if(!GLOB.station_account)
		create_station_account()

	if(!GLOB.current_date_string)
		GLOB.current_date_string = "[time2text(world.timeofday, "DD Month")], [GLOB.year_integer]"

	machine_id = "[station_name()] Acc. DB #[GLOB.num_financial_terminals++]"
	..()

/obj/machinery/computer/account_database/proc/accounting_letterhead(report_name)
	var/datum/ui_login/L = ui_login_get()
	return {"
		<center><h1><b>[report_name]</b></h1></center>
		<center><small><i>[station_name()] Accounting Report</i></small></center>
		<u>Generated By:</u> [L?.id?.registered_name ? L.id.registered_name : "Unknown"], [L?.id?.assignment ? L.id.assignment : "Unknown"]<br>
		<hr>
	"}

/obj/machinery/computer/account_database/attackby(obj/O, mob/user, params)
	if(ui_login_attackby(O, user))
		add_fingerprint(user)
		return
	return ..()

/obj/machinery/computer/account_database/attack_hand(mob/user)
	if(..())
		return TRUE

	add_fingerprint(user)
	ui_interact(user)

/obj/machinery/computer/account_database/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "AccountsUplinkTerminal", name, 800, 600, master_ui, state)
		ui.open()

/obj/machinery/computer/account_database/ui_data(mob/user)
	var/list/data = list()
	data["currentPage"] = current_page
	data["is_printing"] = (next_print > world.time)
	ui_login_data(data, user)
	if(data["loginState"]["logged_in"])
		switch(current_page)
			if(AUT_ACCLST)
				var/list/accounts = list()
				for(var/i in 1 to length(GLOB.all_money_accounts))
					var/datum/bank_account/D = GLOB.all_money_accounts[i]
					accounts.Add(list(list(
						"account_id" = D.account_id,
						"account_holder" = D.account_holder,
						"transferable" = D.transferable ? "transferable" : "Active",
						"account_index" = i)))

				data["accounts"] = accounts

			if(AUT_ACCINF)
				data["account_id"] = detailed_account_view.account_id
				data["account_holder"] = detailed_account_view.account_holder
				data["money"] = detailed_account_view.account_balance
				data["transferable"] = detailed_account_view.transferable

				var/list/transactions = list()
				for(var/datum/transaction/T in detailed_account_view.transaction_history)
					transactions.Add(list(list(
						"date" = T.date,
						"time" = T.time,
						"target_name" = T.target_name,
						"purpose" = T.purpose,
						"amount" = T.amount,
						"source_terminal" = T.source_terminal)))

				data["transactions"] = transactions
	return data


/obj/machinery/computer/account_database/ui_act(action, list/params)
	if(..())
		return

	. = TRUE

	if(ui_login_act(action, params))
		return

	if(!ui_login_get().logged_in)
		return

	switch(action)
		if("view_account_detail")
			var/index = text2num(params["index"])
			if(index && index > 0 && index <= length(GLOB.all_money_accounts))
				detailed_account_view = GLOB.all_money_accounts[index]
				current_page = AUT_ACCINF

		if("back")
			detailed_account_view = null
			current_page = AUT_ACCLST

		if("toggle_suspension")
			if(detailed_account_view)
				detailed_account_view.transferable = !detailed_account_view.transferable

		if("create_new_account")
			current_page = AUT_ACCNEW

		if("finalise_create_account")
			var/account_name = params["holder_name"]
			var/starting_funds = max(text2num(params["starting_funds"]), 0)
			if(!account_name || !starting_funds)
				return

			starting_funds = clamp(starting_funds, 0, GLOB.station_account.account_balance) // Not authorized to put the station in debt.
			starting_funds = min(starting_funds, fund_cap) // Not authorized to give more than the fund cap.

			var/datum/bank_account/M = create_account(account_name, starting_funds, src)
			if(starting_funds > 0)
				GLOB.station_account.charge(starting_funds, null, "New account activation", "", "New account activation", M.account_holder)

			current_page = AUT_ACCLST


		if("print_records")
			// Anti spam measures
			if(next_print > world.time)
				to_chat(usr, "<span class='warning'>The printer is busy spooling. It will be ready in [(next_print - world.time) / 10] seconds.")
				return
			var/text
			playsound(loc, 'sound/goonstation/machines/printer_thermal.ogg', 50, 1)
			var/obj/item/paper/P = new(loc)
			P.name = "financial account list"
			text = {"
				[accounting_letterhead("Financial Account List")]

				<table>
					<thead>
						<tr>
							<td>Account Number</td>
							<td>Holder</td>
							<td>Balance</td>
							<td>Status</td>
						</tr>
					</thead>
					<tbody>
			"}

			for(var/i in 1 to length(GLOB.all_money_accounts))
				var/datum/bank_account/D = GLOB.all_money_accounts[i]
				text += {"
						<tr>
							<td>#[D.account_id]</td>
							<td>[D.account_holder]</td>
							<td>$[D.account_balance]</td>
							<td>[D.transferable ? "transferable" : "Active"]</td>
						</tr>
				"}

			text += {"
					</tbody>
				</table>
			"}

			P.default_raw_text = text
			visible_message("<span class='notice'>[src] prints out a report.</span>")
			next_print = world.time + 30 SECONDS

		if("print_account_details")
			// Anti spam measures
			if(next_print > world.time)
				to_chat(usr, "<span class='warning'>The printer is busy spooling. It will be ready in [(next_print - world.time) / 10] seconds.")
				return
			var/text
			playsound(loc, 'sound/goonstation/machines/printer_thermal.ogg', 50, 1)
			var/obj/item/paper/P = new(loc)
			P.name = "account #[detailed_account_view.account_id] details"
			var/title = "Account #[detailed_account_view.account_id] Details"
			text = {"
				[accounting_letterhead(title)]
				<u>Holder:</u> [detailed_account_view.account_holder]<br>
				<u>Balance:</u> $[detailed_account_view.account_balance]<br>
				<u>Status:</u> [detailed_account_view.transferable ? "transferable" : "Active"]<br>
				<u>Transactions:</u> ([detailed_account_view.transaction_history.len])<br>
				<table>
					<thead>
						<tr>
							<td>Timestamp</td>
							<td>Target</td>
							<td>Reason</td>
							<td>Value</td>
							<td>Terminal</td>
						</tr>
					</thead>
					<tbody>
				"}

			for(var/datum/transaction/T in detailed_account_view.transaction_history)
				text += {"
							<tr>
								<td>[T.date] [T.time]</td>
								<td>[T.target_name]</td>
								<td>[T.purpose]</td>
								<td>[T.amount]</td>
								<td>[T.source_terminal]</td>
							</tr>
					"}

			text += {"
					</tbody>
				</table>
				"}

			P.default_raw_text = text
			visible_message("<span class='notice'>[src] prints out a report.</span>")
			next_print = world.time + 30 SECONDS

#undef AUT_ACCLST
#undef AUT_ACCINF
#undef AUT_ACCNEW
