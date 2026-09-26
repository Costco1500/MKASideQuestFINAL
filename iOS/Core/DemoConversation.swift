import Foundation

public enum DemoConfiguration {
    #if DEBUG && targetEnvironment(simulator)
    public static var preloadConversation = true
    #else
    public static let preloadConversation = false
    #endif
}

/// Fictional input only. Plans, locations, votes and Calendar all use the real app flow.
public enum DemoConversation {
    public static var messages: [ImportedMessage] {
        var messages = MessageImport.parse(transcript)
        MessageImport.select(.latest50, in: &messages)
        return messages
    }
    public static let transcript = """
    Alex: who left a blue hoodie in the library
    Jake: if it has a coffee stain it's probably mine
    Maya: that describes every hoodie you own
    Sarah: can confirm
    Jake: rude but fair
    Alex: anyway are we actually doing something this Thursday
    Maya: PLEASE. i need one evening that isn't my laptop
    Sarah: same, this week has been a lot
    Jake: i'm down after 6, last class ends at 5:45
    Alex: lab runs until 6:30 for me but after that i'm free
    Maya: 6:30 is good. nothing early friday
    Sarah: i'm free 5 to 10, just need to be back by 10
    Jake: also unrelated did anyone do the laundry room thing
    Maya: what laundry room thing
    Jake: there's one sock taped to the door with a missing poster
    Sarah: campus journalism is thriving
    Alex: serious idea though, what about making something
    Maya: pottery!! i've been wanting to try it forever
    Jake: i support anything where i can make a terrible mug
    Sarah: something small and low pressure sounds nice
    Maya: doesn't have to be a whole class, air dry clay works too
    Alex: and then boba after?
    Maya: yes please
    Jake: can we keep it around $15 each? rent week is winning
    Sarah: $15 would be ideal for me too
    Alex: works for me, let's keep it cheap
    Sarah: also can we skip the packed loud restaurants this time
    Maya: agree, last week i couldn't hear a single sentence
    Jake: quiet spot, small group, zero yelling. noted
    Alex: i'm on campus near tech square
    Maya: i'll be in Midtown already
    Jake: coming from Buckhead but can meet halfway
    Sarah: i'm near GT, happy to walk a bit if the weather holds
    Maya: forecast looks okay but maybe have an indoor option
    Jake: bringing the hoodie back is my side quest apparently
    Alex: so thursday after 6:30, chill, under $15, something creative and maybe boba
    Sarah: that sounds like exactly the kind of night i need
    Maya: sold. someone make this a real plan
    """
}
