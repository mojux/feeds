#import "TrelloAccount.h"

@implementation TrelloAccount

+ (void)load { [Account registerClass:self]; }
+ (BOOL)requiresDomain { return NO; }
+ (BOOL)requiresUsername { return NO; }
+ (BOOL)requiresPassword { return NO; }
+ (NSURL *)requiredAuthURL {
    return [NSURL URLWithString:@"https://trello.com/1/connect?key=53e6bb99cefe4914e88d06c76308e357&name=Feeds&return_url=feedsapp://trello/auth"];
}

- (void)authWasFinishedWithURL:(NSURL *)url {
    NSString *fragment = [url fragment]; // #token=xyz
    
    if (![fragment beginsWithString:@"token="]) {
        [self.delegate account:self validationDidFailWithMessage:@"" field:AccountFailingFieldAuth];
        return;
    }
    
    NSArray *parts = [fragment componentsSeparatedByString:@"="];
    NSString *token = [parts objectAtIndex:1]; // xyz
    
    [self validateWithPassword:token];
}

- (void)validateWithPassword:(NSString *)token {

    NSString *URL = [NSString stringWithFormat:@"https://api.trello.com/1/members/me?key=53e6bb99cefe4914e88d06c76308e357&token=%@", token];
    
    self.request = [SMWebRequest requestWithURL:[NSURL URLWithString:URL] delegate:nil context:token];
    [request addTarget:self action:@selector(meRequestComplete:context:) forRequestEvents:SMWebRequestEventComplete];
    [request addTarget:self action:@selector(meRequestError:) forRequestEvents:SMWebRequestEventError];
    [request start];
}

- (void)meRequestComplete:(NSData *)data context:(NSString *)token {
    
    NSDictionary *me = [data objectFromJSONData];
    self.username = [me objectForKey:@"username"];

    NSString *mainFeedString = [NSString stringWithFormat:@"https://api.trello.com/1/members/me/notifications?key=53e6bb99cefe4914e88d06c76308e357&token=%@", token];
    Feed *mainFeed = [Feed feedWithURLString:mainFeedString title:@"All Notifications" author:self.username account:self];
    
    self.feeds = [NSArray arrayWithObject:mainFeed];
    
    [self.delegate account:self validationDidCompleteWithPassword:token];
}

- (void)meRequestError:(NSError *)error {
    NSLog(@"Error! %@", error);
    [self.delegate account:self validationDidFailWithMessage:error.localizedDescription field:AccountFailingFieldUnknown];
}

+ (NSArray *)itemsForRequest:(SMWebRequest *)request data:(NSData *)data {
    if ([request.request.URL.host isEqualToString:@"api.trello.com"]) {
        
        NSMutableArray *items = [NSMutableArray array];
        NSArray *notifications = [data objectFromJSONData];

        // cache this, it's expensive to create (and not threadsafe)
        ISO8601DateFormatter *formatter = [[[ISO8601DateFormatter alloc] init] autorelease];
        
        for (NSDictionary *notification in notifications) {
            
            FeedItem *item = [[FeedItem new] autorelease];
            
            NSString *type = [notification objectForKey:@"type"];
            NSString *date = [notification objectForKey:@"date"];
            NSDictionary *data = [notification objectForKey:@"data"];
            NSDictionary *org = [[data objectForKey:@"organization"] objectForKey:@"id"];
            NSDictionary *board = [[data objectForKey:@"board"] objectForKey:@"id"];
            NSDictionary *card = [[data objectForKey:@"card"] objectForKey:@"id"];
            NSString *URLString = nil;

            item.published = [formatter dateFromString:date];
            item.updated = item.published;
            
            if (!item.published) NSLog(@"Couldn't parse date %@", date);

            if (card && board)
                URLString = [NSString stringWithFormat:@"https://trello.com/card/board/%@/%@",board,card];
            else if (board)
                URLString = [NSString stringWithFormat:@"https://trello.com/board/%@",board];
            else if (org)
                URLString = [NSString stringWithFormat:@"https://trello.com/org/%@",org];
  
            if (URLString)
                item.link = [NSURL URLWithString:URLString];

            NSString *title = nil;
            
            if ([type isEqualToString:@"addedToBoard"])
                title = @"added to board {board}";
            else if ([type isEqualToString:@"addedToCard"])
                title = @"added to card {card}";
            else if ([type isEqualToString:@"addAdminToBoard"])
                title = @"added as admin to board {board}";
            else if ([type isEqualToString:@"addAdminToOrganization"])
                title = @"added as admin to organization {org}";
            else if ([type isEqualToString:@"changeCard"])
                title = @"changed card {card}";
            else if ([type isEqualToString:@"closeBoard"])
                title = @"closed board {board}";
            else if ([type isEqualToString:@"commentCard"])
                title = @"comment on card {card}";
            else if ([type isEqualToString:@"invitedToBoard"])
                title = @"invited to board {board}";
            else if ([type isEqualToString:@"invitedToOrganization"])
                title = @"invited to organization {org}";
            else if ([type isEqualToString:@"removedFromBoard"])
                title = @"removed from board {board}";
            else if ([type isEqualToString:@"removedFromCard"])
                title = @"removed from card {card}";
            else if ([type isEqualToString:@"removedFromOrganization"])
                title = @"removed from organization {org}";
            else if ([type isEqualToString:@"mentionedOnCard"])
                title = @"mentioned on card {card}";
            else
                title = type;
            
            title = [title stringByReplacingOccurrencesOfString:@"{org}" withString:
                     [[data objectForKey:@"organization"] objectForKey:@"name"] ?: @""];
            title = [title stringByReplacingOccurrencesOfString:@"{board}" withString:
                     [[data objectForKey:@"board"] objectForKey:@"name"] ?: @""];
            title = [title stringByReplacingOccurrencesOfString:@"{card}" withString:
                     [[data objectForKey:@"card"] objectForKey:@"name"] ?: @""];
            
            item.title = title;
            item.author = @"";
            item.content = [data objectForKey:@"text"];
            
            [items addObject:item];
        }
        
        return items;
    }
    else return nil;
}

@end