-- Presentation decisions only. Inventory, cart, sale and quest owners remain authoritative.
local M={}
function M.New()
 return {cartEver=false,pushDone=false,storedEver=false,lightDone=false,crouchDone=false,standDone=false,returningSeen=false}
end
function M.Observe(s,o)
 -- Only this player's own grab counts: a teammate holding it or loot already stored does not tick the cart step.
 if o.cartMine or o.sold>0 then s.cartEver=true end
 -- A cart already holding the quota skips the push-to-item lesson: the next card is the van, never another item.
 if s.cartEver and(o.cartMoved>=8 or o.sold>0 or o.cartValue>0 and o.sold+o.cartValue>=o.quota)then s.pushDone=true end
 if o.cartValue>0 or o.cargoCount>0 or o.sold>0 then s.storedEver=true end
 -- An item in the cart means the cart lessons are learned too (no going back to 'grab the cart').
 if s.storedEver then s.cartEver=true;s.pushDone=true end
 if o.lightUsed then s.lightDone=true end
 if o.crouching then s.crouchDone=true elseif s.crouchDone then s.standDone=true end
 if o.phase=='Returning' then s.returningSeen=true end
end
local function step(id,goal,action,shared)
 return {id=id,goal=goal,action=action,shared=shared==true}
end
local decide
function M.Decide(s,o)
 local result=decide(s,o)
 s.last=result and result.id or nil
 return result
end
decide=function(s,o)
 -- In a party, a player who never pushed the cart (or died) still finishes onboarding when the team clears the level.
 if o.phase=='Returning' then s.returningSeen=true end
 if o.active and(o.teamSize or 1)>1 and(o.phase=='Won' or o.round>1 and s.returningSeen)then return step('complete',nil,nil,true)end
 if not o.alive or not o.active then return nil end
 M.Observe(s,o)
 if o.phase=='Deploying' or not o.cartReady then return step('loading',nil,nil,true)end
 if o.phase=='Selling' then return step('selling','van',nil,true)end
 -- Anyone can collect while another teammate pushes. A held item always gets a basket instruction.
 -- No 'stored' pause: the next instruction shows the moment an item lands in the cart.
 -- After the first stored item the player is on their own (owner 2026-10-26): no hold/aim/drop cards again.
 if o.heldItem and not s.storedEver then
  if o.itemOverBasket then return step('releaseItem','basket','release',true)end
  -- Hysteresis: once aiming, stay on 'aim' until 9.5 studs away (the edge used to flip the card back and forth).
  if o.cartDistance<=(s.last=='aimBasket'and 9.5 or 7)then return step('aimBasket','basket','hold',true)end
  return step('bringItem','basket','hold',true)
 end
 if not s.cartEver then
  if o.cartHeldBy~=nil then return step('waitCart','cart',nil,true)end
  return step('grabCart','cart','grab',false)
 end
 if not s.pushDone then
  if o.cartHeldBy==nil then return step('regrabCart','cart','grab',true)end
  if o.targetCartDistance<=11 then s.pushDone=true
  else return step(o.cartMine and 'pushCart' or 'followCart','item',o.cartMine and 'hold' or 'move',true)end
 end
 -- Flashlight and crouch wait for the first sale, so the first minutes are only cart, item, van.
 if o.sold>0 and o.phase~='Selling'then
  if not s.crouchDone then return step('crouch',nil,'crouch',false)end
  if not s.standDone then return step('stand',nil,'crouch',false)end
 end
 if o.phase=='Won' or o.round>1 and s.returningSeen then return step('complete',nil,nil,true)end
 if o.phase=='Returning' or o.sold>=o.quota then return step('extract','van','move',true)end
 -- First sale waits for two items in the cart (or no loot left to find), so the player collects both before selling.
 -- The van card waits until the cart holds the quota (about five items on level 1), or the map has no loot left.
 local ready=o.cartValue>0 and(o.sold+o.cartValue>=o.quota or o.sold==0 and not o.target)
 if ready then
  if o.cartHeldBy==nil then return step('grabToSell','cart','grab',true)end
  if o.cartAtVan then return step('waitForSale','van',nil,true)end -- sells while held: no 'let go' step
  return step(o.cartMine and 'pushToVan' or 'followToVan','van',o.cartMine and 'hold' or 'move',true)
 end
 -- Owner 2026-10-26: after the first item one card says 'find items and put them in the cart', then it disappears
 -- until the cart holds enough; the player learns the rest from that first item.
 if s.storedEver then
  s.findUntil=s.findUntil or os.clock()+6
  if os.clock()<s.findUntil then return step('findItems',nil,nil,true)end
  return nil
 end
 if not o.target then return step('findLoot','cart',nil,true)end
 -- Hysteresis around the 11-stud item-to-cart edge: switch to 'bring the cart' at 13, back to 'pick it up' at 11.
 local nearItem=s.last=='parkCart'or s.last=='pickFirstItem'
 -- Only the first item has the cart brought to it (owner 2026-10-25): after that the player knows how to push it, so
 -- the next card sends them straight to the item to carry back.
 if not s.storedEver and o.targetCartDistance>(nearItem and 13 or 11)then
  if o.cartHeldBy==nil then return step('regrabCart','cart','grab',true)end
  return step(o.cartMine and 'nextItem' or 'helpCollect','item',o.cartMine and 'hold' or 'grab',true)
 end
 -- Park the cart only before the first item (owner 2026-10-25): from the second item on, the next card is the item itself.
 if o.cartMine and not s.storedEver then return step('parkCart','cart','release',true)end
 return step('pickFirstItem','item','grab',true)
end
return M
