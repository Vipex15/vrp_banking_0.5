-- Define the Banking class and related functions
local Banking = class("Banking", vRP.Extension)

Banking.User = class("User")
Banking.event = {}
Banking.tunnel = {}

local htmlEntities = module("lib/htmlEntities")

-- Register menu builder for displaying user transactions
local function transactions_menu(self)
    vRP.EXT.GUI:registerMenuBuilder("Your Transactions", function(menu)
        menu.title = "Your Transactions"
        menu.css.header_color = "rgba(255,125,0,0.75)"
        
        local user = vRP.users_by_source[menu.user.source]
        local character_id = user.cid

        if character_id then 
            local transactions = Banking:GetUserTransactions(character_id)
            
            if next(transactions) then
                table.sort(transactions, function(a, b)
                    if a.transaction_date == b.transaction_date then
                        return a.transaction_hours > b.transaction_hours
                    else
                        return a.transaction_date > b.transaction_date
                    end
                end)
                for index, transaction in ipairs(transactions) do
                    local transaction_info = string.format("Transaction %d:<br>Type: %s<br>Amount: %s$<br>Transfer to: %s<br>Date: %s <br>Hours:%s",  index, transaction.transaction_type, transaction.amount, transaction.transfer_to,transaction.transaction_date, transaction.transaction_hours)    
                    menu:addOption("Transaction " .. index, nil, transaction_info)
                end
            else
                menu:addOption("No Transactions", nil, "You have no transactions.")
            end
        end
    end)
end

-- Callback function to open the transaction menu
local function see_transactions(menu)
    local user = menu.user
    user:openMenu("Your Transactions")
end

-- Function to handle withdrawal from the bank
function Banking:withdraw(amount)
    local user = vRP.users_by_source[source]
    if user then
        local user_id = user.id
        local character_id = user.cid
        local balance = user:getBank()
        amount = tonumber(amount)
        if amount and amount <= balance then
            if tonumber(amount) then
                local transaction_date = os.date("%Y-%m-%d %H:%M:%S")
                local transaction_type = "Withdraw"
                exports.oxmysql:execute("INSERT IGNORE INTO vrp_banks_transactions (character_id, transaction_type, amount, transfer_to, transaction_date) VALUES (?, ?, ?, ?, ?)",  {character_id, transaction_type, amount, nil, transaction_date}, function()
                                       
                    vRP.EXT.Base.remote._notify(user_id, "Withdrawn: $" .. amount)
                end)
            end
        else
            vRP.EXT.Base.remote._notify(user_id, "Not enough funds in your bank account")
        end
    end
end

-- Function to handle deposit into the bank
function Banking:deposit(amount)
    local user = vRP.users_by_source[source]
    if user then
        local user_id = user.id
        local character_id = user.cid
        local balance = user:getWallet()
        amount = tonumber(amount)
        if amount and amount <= balance then                
            if user:tryDeposit(amount) then
                local transaction_date = os.date("%Y-%m-%d %H:%M:%S")
                local transaction_type = "Deposit"
                exports.oxmysql:execute("INSERT IGNORE INTO vrp_banks_transactions (character_id, transaction_type, amount, transfer_to, transaction_date) VALUES (?, ?, ?, ?, ?)",  {character_id, transaction_type, amount, nil, transaction_date}, function()
                                        
                    vRP.EXT.Base.remote._notify(user_id, "Deposited: $" .. amount)
                end)
            else
                vRP.EXT.Base.remote._notify(user_id, "Failed to deposit funds.")
            end
        else
            vRP.EXT.Base.remote._notify(user_id, "Invalid deposit amount or insufficient balance.")
        end
    end
end

-- Function to handle money transfer between users
function Banking:transfer(transfer, to)
    local user = vRP.users_by_source[source]
    local character_id = user.cid
    local tuser = vRP.users_by_source[to]                
    
    local balance = user:getBank()
             
    if tuser ~= nil then
        if balance <= 0 or balance < tonumber(transfer) or tonumber(transfer) <= 0 then
            vRP.EXT.Base.remote._notify(user.source, "You don't have enough money to transfer.")
        else
            local user_bank = balance - tonumber(transfer)
            user:setBank(user_bank)
            tuser:giveBank(tonumber(transfer))
            vRP.EXT.Base.remote._notify(user.source, string.format("You transferred $%d to %s.", tonumber(transfer), tuser.name))
            vRP.EXT.Base.remote._notify(tuser.source, string.format("You received a transfer of $%d from %s.", tonumber(transfer), user.name))
            
            local transaction_date = os.date("%Y-%m-%d %H:%M:%S")
            local transaction_type = "Transfer"
            local transfer_to = tuser.cid
            
            exports.oxmysql:execute("INSERT IGNORE INTO vrp_banks_transactions (character_id, transaction_type, amount, transfer_to, transaction_date) VALUES (?, ?, ?, ?, ?)",{character_id, transaction_type, transfer, transfer_to, transaction_date}, function()
            end)
        end
    else
        vRP.EXT.Base.remote._notify(user.source, "Recipient not found.")
    end
end

-- Function to retrieve user transactions from the database
function Banking:GetUserTransactions(character_id)
    local transactions = {} 
    local rows = exports.oxmysql:executeSync("SELECT transaction_type, amount, transfer_to, DATE_FORMAT(transaction_date, '%d-%m-%Y') AS formatted_date, DATE_FORMAT(transaction_date, '%H:%i:%s') AS formatted_hours FROM vrp_banks_transactions WHERE character_id = ?", {character_id})
    if rows then
        for _, row in ipairs(rows) do
            local transaction = {
                transaction_type = row.transaction_type,
                amount = row.amount,
                transfer_to = row.transfer_to,
                transaction_date = row.formatted_date,
                transaction_hours = row.formatted_hours
            }
            table.insert(transactions, transaction) 
        end
    end
    return transactions
end

-- Register bank functions for every player
local function BankFunctions()
    vRP.EXT.GUI:registerMenuBuilder("Bank Functions", function(menu)
        menu.title = "Bank Functions"
        menu.css.header_color = "rgba(0,255,0,0.75)"
        local user = vRP.users_by_source[menu.user.source]
        local character_id = user.cid
        if character_id then 
            local identity = vRP.EXT.Identity:getIdentity(character_id)

            menu:addOption("Account Info", nil, string.format(identity.firstname.." "..identity.name.." account:<br>Wallet Balance: %s<br>Bank Balance: %s",
            htmlEntities.encode(user:getWallet()), htmlEntities.encode(user:getBank())))

            menu:addOption("Transactions", see_transactions,"Your Transactions")
                
            menu:addOption("Deposit Money", function()
                local deposit_amount = user:prompt("Enter the amount to deposit:", "")
                Banking:deposit(deposit_amount)
                user:actualizeMenu(menu)
            end, "Deposit funds into your bank account:")
                
            menu:addOption("Withdraw Funds", function()
                local withdraw_amount = user:prompt("Enter the amount to withdraw:", "")
                Banking:withdraw(withdraw_amount)
                user:actualizeMenu(menu)
            end, "Withdraw funds from your bank account:")

            menu:addOption("Transfer", function()
                local to = user:prompt("Enter character ID to transfer:", "")
                local transfer = user:prompt("Enter amount to transfer:", "")
                Banking:transfer(transfer, to)
                user:actualizeMenu(menu)
            end)
        end
    end)
end 

-- Register menu builder for police PC transactions
local function menu_police_pc_trans(self)
    vRP.EXT.GUI:registerMenuBuilder("Transactions", function(menu)
        local user = menu.user
        local reg = user:prompt("Enter character ID:", "")
        
        if reg then 
            local cid = vRP.EXT.Identity:getByRegistration(reg)
            if cid then
                local identity = vRP.EXT.Identity:getIdentity(cid)
                if identity then
                    local character_id = identity.character_id 
                    menu.title = identity.firstname.." "..identity.name
                    menu.css.header_color = "rgba(0,255,0,0.75)"           
                     
                    if character_id then
                        local transactions = Banking:GetUserTransactions(character_id)
                        if next(transactions) then
                            table.sort(transactions, function(a, b)
                                if a.transaction_date == b.transaction_date then
                                    return a.transaction_hours > b.transaction_hours
                                else
                                    return a.transaction_date > b.transaction_date
                                end
                            end)
                            for index, transaction in ipairs(transactions) do
                                local transaction_info = string.format("Transaction %d:<br>Type: %s<br>Amount: %s$<br>Transfer to: %s<br>Date: %s <br>Hours:%s", index, transaction.transaction_type, transaction.amount, transaction.transfer_to,  transaction.transaction_date, transaction.transaction_hours)
                                menu:addOption("Transaction " .. index, nil, transaction_info)
                            end
                        else
                            vRP.EXT.Base.remote._notify(user.source, "No transactions found for this player.")
                        end
                    else
                        vRP.EXT.Base.remote._notify(user.source, "Character ID not found for this player.")
                    end
                else
                    vRP.EXT.Base.remote._notify(user.source, "Identity not found for this registration.")
                end
            else
                vRP.EXT.Base.remote._notify(user.source, "No character found with this registration.")
            end
        else
            vRP.EXT.Base.remote._notify(user.source, "Character ID not entered.")
        end
    end)

    local function police_se_transactions(menu)
        local user = menu.user
        user:openMenu("Transactions")
    end

    vRP.EXT.GUI:registerMenuBuilder("police_pc", function(menu)
        local user = menu.user
        if user:hasGroup("police") then 
            menu:addOption("Transactions", police_se_transactions, "See player information")
        end
    end)
end

-- Constructor for the Banking class
function Banking:__construct()
    vRP.Extension.__construct(self)
    
    self.cfg = module("vrp_banking", "cfg/cfg")

    -- Load async
    async(function()
        vRP:prepare("vRP/banks", [[     
            CREATE TABLE IF NOT EXISTS vrp_banks_transactions (
                id INT AUTO_INCREMENT PRIMARY KEY,
                character_id INT NOT NULL, 
                transaction_type ENUM('Deposit', 'Withdraw', 'Transfer') NOT NULL,
                transfer_to VARCHAR(255) NOT NULL,
                amount DECIMAL(12) NOT NULL,
                transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );            
            ]])
        vRP:execute("vRP/banks")
    end)
          
    BankFunctions()
    transactions_menu(self)
    menu_police_pc_trans(self)
end

-- Event handler for player spawn
function Banking.event:playerSpawn(user, first_spawn)
    if first_spawn then
        for k,v in pairs(self.cfg.banks) do
            local bank_locations = v.bank_entry
            local Bankx, Banky, Bankz = bank_locations.x, bank_locations.y, bank_locations.z
            local function BankFuncitons(user)
                user:openMenu("Bank Functions")
            end
            local function BankFuncitonsLeave(user)
                user:closeMenu("Bank Functions")
            end
            local bank_info = {"PoI", {blip_id = 108, blip_color = 69, marker_id = 1}}
            local ment = clone(bank_info)
            ment[2].pos = {Bankx, Banky, Bankz - 1}
            vRP.EXT.Map.remote._addEntity(user.source, ment[1], ment[2])
    
            user:setArea("vRP:vrp_banking:BankFuncitons:" .. k, Bankx, Banky, Bankz, 1, 1.5, BankFuncitons, BankFuncitonsLeave)
        end
    end
end

vRP:registerExtension(Banking)
