//
//  BRSendViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

// Updated by Farrukh Askari <farrukh.askari01@gmail.com> on 3:22 PM 17/4/17.

#import "BRSendViewController.h"
#import "BRRootViewController.h"
#import "BRScanViewController.h"
#import "BRAmountViewController.h"
#import "BRSendBalanceViewController.h"
#import "BRSettingsViewController.h"
#import "BRReceiveViewController.h"
#import "BRBubbleView.h"
#import "BRWalletManager.h"
#import "BRPeerManager.h"
#import "BRPaymentRequest.h"
#import "BRPaymentProtocol.h"
#import "BRKey.h"
#import "BRTransaction.h"
#import "NSString+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "BREventManager.h"
#import "FinancialGate-Swift.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import "UIImage+Utils.h"
#import "BRAppGroupConstants.h"
#import "BRWalletManager.h"


#define SCAN_TIP      NSLocalizedString(@"Scan someone else's QR code to get their bitcoin address. "\
                                         "You can send a payment to anyone with an address.", nil)
#define CLIPBOARD_TIP NSLocalizedString(@"Bitcoin addresses can also be copied to the clipboard. "\
                                         "A bitcoin address always starts with '1' or '3'.", nil)

#define LOCK @"\xF0\x9F\x94\x92" // unicode lock symbol U+1F512 (utf-8)
#define REDX @"\xE2\x9D\x8C"     // unicode cross mark U+274C, red x emoji (utf-8)
#define NBSP @"\xC2\xA0"         // no-break space (utf-8)

#define QR_IMAGE_FILE [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject\ 
                       stringByAppendingPathComponent:@"qr.png"]

static NSString *sanitizeString(NSString *s)
{
    NSMutableString *sane = [NSMutableString stringWithString:(s) ? s : @""];
    
    CFStringTransform((CFMutableStringRef)sane, NULL, kCFStringTransformToUnicodeName, NO);
    return sane;
}

@interface BRSendViewController ()

@property (nonatomic, assign) BOOL clearClipboard, useClipboard, showTips, showBalance, canChangeAmount;
@property (nonatomic, strong) BRTransaction *sweepTx;
@property (nonatomic, strong) BRPaymentProtocolRequest *request;
@property (nonatomic, strong) NSURL *url, *callback;
@property (nonatomic, assign) double amount;
@property (nonatomic, strong) NSString *okAddress, *okIdentity;
@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, strong) BRScanViewController *scanController;
@property (nonatomic, strong) id clipboardObserver;
@property (nonatomic, strong) NSUserDefaults *groupDefs;
@property (nonatomic, strong) BRPaymentRequest *paymentRequest;
@property (nonatomic, strong) UIImage *qrImage;
@property (nonatomic, assign) double balance;

@property (nonatomic, strong) IBOutlet UILabel *sendLabel;
@property (nonatomic, strong) IBOutlet UIButton *scanButton, *clipboardButton;
@property (nonatomic, strong) IBOutlet UITextView *clipboardText;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *clipboardXLeft;
@property (weak, nonatomic) IBOutlet UIImageView *qrView;
@property (weak, nonatomic) IBOutlet UILabel *btc;
@property (weak, nonatomic) IBOutlet UILabel *money;
@property (weak, nonatomic) IBOutlet UIButton *sendButton;
@property (weak, nonatomic) IBOutlet UIButton *receieveButton;
@property (nonatomic, strong) IBOutlet UIGestureRecognizer *navBarTap;
@property (weak, nonatomic) IBOutlet UILabel *address;

@property (nonatomic, strong) id urlObserver, fileObserver, protectedObserver, balanceObserver, seedObserver;


@end

@implementation BRSendViewController

int check = 1;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // TODO: XXX redesign page with round buttons like the iOS power down screen... apple watch also has round buttons
    self.scanButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.clipboardButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.scanButton.titleLabel.adjustsLetterSpacingToFitWidth = YES;
    self.clipboardButton.titleLabel.adjustsLetterSpacingToFitWidth = YES;
#pragma clang diagnostic pop
    
    self.clipboardText.textContainerInset = UIEdgeInsetsMake(8.0, 0.0, 0.0, 0.0);
    
    self.clipboardObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIPasteboardChangedNotification object:nil queue:nil
                                                                           usingBlock:^(NSNotification *note) {
        if (self.clipboardText.isFirstResponder) {
            self.useClipboard = YES;
        } else {
            [self updateClipboardText];
        }
    }];
    
    // Code
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:YES];
    [self updateBalance];
    [self updateAddress];
    // END Address
    
    self.balanceObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) {
        double progress = [BRPeerManager sharedInstance].syncProgress;
          
        if (_balance != UINT64_MAX && progress > DBL_EPSILON && progress + DBL_EPSILON < 1.0) { // wait for sync
            self.balance = _balance; // this updates the local currency value with the latest exchange rate
            return;
        }
          
        [self updateBalance];
        [self updateAddress];
    }];
    // END Code
}

- (void)updateAddress {
    BRPaymentRequest *req;
    self.groupDefs = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_ID];
    req = (_paymentRequest) ? _paymentRequest :
    [BRPaymentRequest requestWithString:[self.groupDefs stringForKey:APP_GROUP_RECEIVE_ADDRESS_KEY]];
    
    //    if (req.isValid) {
    if (! _qrImage) {
        _qrImage = [[UIImage imageWithContentsOfFile:QR_IMAGE_FILE] resize:self.qrView.bounds.size withInterpolationQuality:kCGInterpolationNone];
    }
    
    self.qrView.image = _qrImage;
    //    }
    
    NSString *address = NSLocalizedString(@"Your current address", nil);
    if (self.paymentRequest.string != nil && ![self.paymentRequest.string  isEqual: @""]) {
        NSString *string = [self.paymentRequest.string stringByReplacingOccurrencesOfString:@"bitcoin:" withString:@""];
        [self.address setText:[NSString stringWithFormat:@"%@: %@", address, string]];
    } else {
        [self.address setText:[NSString stringWithFormat:@"%@: %@", address, req.paymentAddress]];
    }
    
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ReceieveButton:)];
    tapGestureRecognizer.numberOfTapsRequired = 1;
    [_address addGestureRecognizer:tapGestureRecognizer];
    _address.userInteractionEnabled = YES;
}

- (IBAction)ReceieveButton:(id)sender {
    
    BRPaymentRequest *req1 = (_paymentRequest) ? _paymentRequest : [BRPaymentRequest requestWithString:[self.groupDefs stringForKey:APP_GROUP_RECEIVE_ADDRESS_KEY]];
    
    if (req1.amount == 0) {
        if (req1.isValid) {
            [self.groupDefs setObject:req1.data forKey:APP_GROUP_REQUEST_DATA_KEY];
            [self.groupDefs setObject:req1.paymentAddress forKey:APP_GROUP_RECEIVE_ADDRESS_KEY];
        } else {
            [self.groupDefs removeObjectForKey:APP_GROUP_REQUEST_DATA_KEY];
            [self.groupDefs removeObjectForKey:APP_GROUP_RECEIVE_ADDRESS_KEY];
        }
        
        [self.groupDefs synchronize];
    }
    
    if ([self nextTip]) return;
    [BREventManager saveEvent:@"receive:address"];
        
    BOOL req = (_paymentRequest) ? YES : NO;
    UIActionSheet *actionSheet = [UIActionSheet new];
    
    if (self.paymentRequest.string != nil && ![self.paymentRequest.string  isEqual: @""]) {
        NSString *string = [self.paymentRequest.string stringByReplacingOccurrencesOfString:@"bitcoin:" withString:@""];
        actionSheet.title = [NSString stringWithFormat:NSLocalizedString(@"Receive bitcoins at this address: %@", nil), string];
    } else {
        actionSheet.title = [NSString stringWithFormat:NSLocalizedString(@"Receive bitcoins at this address: %@", nil), req1.paymentAddress];
    }
   
    actionSheet.delegate = self;
    [actionSheet addButtonWithTitle:(req) ? NSLocalizedString(@"copy request to clipboard", nil) :
    NSLocalizedString(@"copy address to clipboard", nil)];
        
    if ([MFMailComposeViewController canSendMail]) {
        [actionSheet addButtonWithTitle:(req) ? NSLocalizedString(@"send request as email", nil) :
        NSLocalizedString(@"send address as email", nil)];
    }
        
#if ! TARGET_IPHONE_SIMULATOR
    if ([MFMessageComposeViewController canSendText]) {
        [actionSheet addButtonWithTitle:(req) ? NSLocalizedString(@"send request as message", nil) :
        NSLocalizedString(@"send address as message", nil)];
    }
#endif
        
    [actionSheet addButtonWithTitle:NSLocalizedString(@"cancel", nil)];
    actionSheet.cancelButtonIndex = actionSheet.numberOfButtons - 1;
        
    [actionSheet showInView:[UIApplication sharedApplication].keyWindow];
}

- (void)updateBalance {
    
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
    self.balance = manager.wallet.balance;
    
    manager.format.maximumFractionDigits = 8;
    NSString *stringWithoutSpaces = [[manager stringForAmount: _balance]
                                     stringByReplacingOccurrencesOfString:@"ƀ" withString:@""];
    
    stringWithoutSpaces = [stringWithoutSpaces stringByReplacingOccurrencesOfString:@"," withString:@""];
    
    CGFloat btcAmount = [stringWithoutSpaces floatValue];
    
    NSString *btcAmountStr = [NSString stringWithFormat:@"%.8f BTC",btcAmount];
    
    _btc.text = btcAmountStr;
    
    _money.text = [manager localCurrencyStringForAmount: _balance];
    
}

- (NSString *)convertToBTC:(uint64_t)amount {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSString *btcAmount = [[manager stringForAmount: amount] stringByReplacingOccurrencesOfString:@"ƀ" withString:@"BTC"];
    return btcAmount;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self cancel:nil];
    
    // Code
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:YES];
    
    BRPaymentRequest *req;
    self.groupDefs = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_ID];
    req = (_paymentRequest) ? _paymentRequest :
    [BRPaymentRequest requestWithString:[self.groupDefs stringForKey:APP_GROUP_RECEIVE_ADDRESS_KEY]];
    
    if (req.isValid) {
        if (! _qrImage) {
            _qrImage = [[UIImage imageWithContentsOfFile:QR_IMAGE_FILE] resize:self.qrView.bounds.size
                                              withInterpolationQuality:kCGInterpolationNone];
        }
        
        self.qrView.image = _qrImage;
    }

    
    self.balanceObserver = [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil queue:nil
                                                                         usingBlock:^(NSNotification *note) {
        double progress = [BRPeerManager sharedInstance].syncProgress;
      
        if (_balance != UINT64_MAX && progress > DBL_EPSILON && progress + DBL_EPSILON < 1.0) { // wait for sync
            self.balance = _balance; // this updates the local currency value with the latest exchange rate
            return;
        }
                                                    
        [self updateBalance];
    }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (! self.scanController) {
        self.scanController = [self.storyboard instantiateViewControllerWithIdentifier:@"ScanViewController"];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    if (self.navBarTap) [self.navigationController.navigationBar removeGestureRecognizer:self.navBarTap];
    self.navBarTap = nil;
    [self hideTips];
    [super viewWillDisappear:animated];
}

- (void)dealloc {
    if (self.clipboardObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.clipboardObserver];
}

- (void)handleURL:(NSURL *)url {
    [BREventManager saveEvent:@"send:handle_url"
               withAttributes:@{@"scheme": (url.scheme ? url.scheme : @"(null)"),
                                @"host": (url.host ? url.host : @"(null)"),
                                @"path": (url.path ? url.path : @"(null)")}];
    
    //TODO: XXX custom url splash image per: "Providing Launch Images for Custom URL Schemes."
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    if ([url.scheme isEqual:@"bread"]) { // x-callback-url handling: http://x-callback-url.com/specifications/
        NSString *xsource = nil, *xsuccess = nil, *xerror = nil, *uri = nil;
        NSURL *callback = nil;

        for (NSString *arg in [url.query componentsSeparatedByString:@"&"]) {
            NSArray *pair = [arg componentsSeparatedByString:@"="]; // if more than one '=', then pair[1] != value

            if (pair.count < 2) continue;

            NSString *value = [[[arg substringFromIndex:[pair[0] length] + 1]
                                stringByReplacingOccurrencesOfString:@"+" withString:@" "]
                                stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

            if ([pair[0] isEqual:@"x-source"]) xsource = value;
            else if ([pair[0] isEqual:@"x-success"]) xsuccess = value;
            else if ([pair[0] isEqual:@"x-error"]) xerror = value;
            else if ([pair[0] isEqual:@"uri"]) uri = value;
        }
    
        if ([url.host isEqual:@"scanqr"] || [url.path isEqual:@"/scanqr"]) { // scan qr
            [self scanQR:self.scanButton];
        }
        else if ([url.host isEqual:@"addresslist"] || [url.path isEqual:@"/addresslist"]) { // copy wallet addresses
            if ((manager.didAuthenticate || [manager authenticateWithPrompt:nil andTouchId:YES])
                && ! self.clearClipboard) {
                
                if (! [self.url isEqual:url]) {
                    self.url = url;
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"copy wallet addresses to clipboard?", nil)
                      message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                      otherButtonTitles:NSLocalizedString(@"copy", nil), nil] show];
                }
                else {
                    [UIPasteboard generalPasteboard].string =
                        [[[manager.wallet.allReceiveAddresses
                           setByAddingObjectsFromSet:manager.wallet.allChangeAddresses]
                        objectsPassingTest:^BOOL(id obj, BOOL *stop) {
                            return [manager.wallet addressIsUsed:obj];
                        }].allObjects componentsJoinedByString:@"\n"];

                    if (xsuccess) callback = [NSURL URLWithString:xsuccess];
                    self.url = nil;
                }
            }
            else if (xerror || xsuccess) {
                callback = [NSURL URLWithString:(xerror) ? xerror : xsuccess];
                [UIPasteboard generalPasteboard].string = @"";
                [self cancel:nil];
            }
        }
        else if ([url.path isEqual:@"/address"] && xsuccess) { // get receive address
            callback = [NSURL URLWithString:[xsuccess stringByAppendingFormat:@"%@address=%@",
                                             ([NSURL URLWithString:xsuccess].query.length > 0) ? @"&" : @"?",
                                             manager.wallet.receiveAddress]];
        }
        else if (([url.host isEqual:@"bitcoin-uri"] || [url.path isEqual:@"/bitcoin-uri"]) && uri &&
                 [[NSURL URLWithString:uri].scheme isEqual:@"bitcoin"]) {
            if (xsuccess) self.callback = [NSURL URLWithString:xsuccess];
            [self handleURL:[NSURL URLWithString:uri]];
        }
        
        if (callback) [[UIApplication sharedApplication] openURL:callback];
    }
    else if ([url.scheme isEqual:@"bitcoin"]) {
        [self confirmRequest:[BRPaymentRequest requestWithURL:url]];
    } else if ([BRBitID isBitIDURL:url]) {
        [self handleBitIDURL:url];
    }
    else {
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"unsupported url", nil)
                                     message:url.absoluteString
                                     preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* yesButton = [UIAlertAction
                                    actionWithTitle:NSLocalizedString(@"ok", nil)
                                    style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction * action) {
                                        [alert dismissViewControllerAnimated:YES completion:nil];
                                    }];
        
        [alert addAction:yesButton];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)handleFile:(NSData *)file {
    BRPaymentProtocolRequest *request = [BRPaymentProtocolRequest requestWithData:file];

    if (request) {
        [self confirmProtocolRequest:request];
        return;
    }

    // TODO: reject payments that don't match requested amounts/scripts, implement refunds
    BRPaymentProtocolPayment *payment = [BRPaymentProtocolPayment paymentWithData:file];
            
    if (payment.transactions.count > 0) {
        for (BRTransaction *tx in payment.transactions) {
            [(id)self.parentViewController.parentViewController startActivityWithTimeout:30];

            [[BRPeerManager sharedInstance] publishTransaction:tx completion:^(NSError *error) {
                [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];
                
                if (error) {
                    UIAlertController * alert = [UIAlertController
                                                 alertControllerWithTitle:NSLocalizedString(@"couldn't transmit payment to bitcoin network", nil)
                                                 message:error.localizedDescription
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    
                    UIAlertAction* yesButton = [UIAlertAction
                                                actionWithTitle:NSLocalizedString(@"ok", nil)
                                                style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * action) {
                                                    [alert dismissViewControllerAnimated:YES completion:nil];
                                                }];
                    
                    [alert addAction:yesButton];
                    
                    [self presentViewController:alert animated:YES completion:nil];
                }

                [self.view addSubview:[[[BRBubbleView
                 viewWithText:(payment.memo.length > 0 ? payment.memo : NSLocalizedString(@"received", nil))
                 center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                 popOutAfterDelay:(payment.memo.length > 0 ? 3.0 : 2.0)]];
            }];
        }

        return;
    }
    
    BRPaymentProtocolACK *ack = [BRPaymentProtocolACK ackWithData:file];
            
    if (ack) {
        if (ack.memo.length > 0) {
            [self.view addSubview:[[[BRBubbleView viewWithText:ack.memo
             center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
             popOutAfterDelay:3.0]];
        }

        return;
    }
    
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"unsupported or corrupted document", nil)
                                 message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* yesButton = [UIAlertAction
                                actionWithTitle:NSLocalizedString(@"ok", nil)
                                style:UIAlertActionStyleDefault
                                handler:^(UIAlertAction * action) {
                                    [alert dismissViewControllerAnimated:YES completion:nil];
                                }];
    
    [alert addAction:yesButton];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleBitIDURL:(NSURL *)url {
    if ([UIAlertController class] == nil) {
        return;
    }
    BRBitID *bitid = [[BRBitID alloc] initWithUrl:url];
    
    void (^actionHandler)(UIAlertAction * _Nonnull) = ^(UIAlertAction * _Nonnull action) {
        [self dismissViewControllerAnimated:YES completion:nil];
        if (action.style == UIAlertActionStyleDefault) {
            BRActivityViewController *activityVC = [[BRActivityViewController alloc] initWithMessage:
                                                    NSLocalizedString(@"Signing...", nil)];
            void (^callbackHandler)(id, id, id) = ^(NSData *data, NSURLResponse *resp, NSError *error) {
                [self.navigationController dismissViewControllerAnimated:YES completion:nil];
                NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;
                if (error == nil && (httpResp.statusCode >= 200 && httpResp.statusCode < 300)) {
                    // successfully sent bitid callback request. show a brief success message
                    UIAlertController *successAlert =
                    [UIAlertController alertControllerWithTitle:@"Successfully Authenticated" message:nil
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    [self.navigationController presentViewController:successAlert animated:YES completion:nil];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                                       [self dismissViewControllerAnimated:YES completion:nil];
                                   });
                } else {
                    // show the user an error alert
                    UIAlertController *errorAlert =
                    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Authentication Error", nil)
                                                        message:NSLocalizedString(@"Please check with the service. "
                                                                                  "You may need to try again.", nil)
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    [errorAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                                   style:UIAlertActionStyleCancel
                                                                 handler:^(UIAlertAction * _Nonnull action) {
                                                                     [self dismissViewControllerAnimated:YES
                                                                                              completion:nil];
                                                                 }]];
                    [self.navigationController presentViewController:errorAlert animated:YES completion:nil];
                }
            };
            // attempt to avoid frozen pin input bug 
            CFRunLoopPerformBlock([[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopCommonModes, ^{
                [bitid runCallback:callbackHandler];
                [self.navigationController presentViewController:activityVC animated:YES completion:nil];
            });
        }
    };
    
    NSString *message = [NSString stringWithFormat:
                         NSLocalizedString(@"%@ is requesting authentication using your bitcoin wallet.", nil),
                         bitid.siteName];
    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"BitID Authentication Request", nil)
                                            message:message preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Deny", nil)
                                                        style:UIAlertActionStyleCancel
                                                      handler:actionHandler]];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Approve", nil)
                                                        style:UIAlertActionStyleDefault
                                                      handler:actionHandler]];
    [self.navigationController presentViewController:alertController animated:YES completion:nil];
}


// generate a description of a transaction so the user can review and decide whether to confirm or cancel
- (NSString *)promptForAmount:(uint64_t)amount fee:(uint64_t)fee address:(NSString *)address name:(NSString *)name
                                                                    memo:(NSString *)memo isSecure:(BOOL)isSecure {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSString *prompt = (isSecure && name.length > 0) ? LOCK @" " : @"";

    //BUG: XXX limit the length of name and memo to avoid having the amount clipped
    if (! isSecure && self.request.errorMessage.length > 0) prompt = [prompt stringByAppendingString:REDX @" "];
    if (name.length > 0) prompt = [prompt stringByAppendingString:sanitizeString(name)];
    if (! isSecure && prompt.length > 0) prompt = [prompt stringByAppendingString:@"\n"];
    if (! isSecure || prompt.length == 0) prompt = [prompt stringByAppendingString:address];
    if (memo.length > 0) prompt = [prompt stringByAppendingFormat:@"\n\n%@", sanitizeString(memo)];
    prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\n\n     amount %@ (%@)", nil),
              [self convertToBTC:amount - fee], [manager localCurrencyStringForAmount:amount - fee]];

    if (fee > 0) {
        prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\nnetwork fee +%@ (%@)", nil),
                  [self convertToBTC:fee], [manager localCurrencyStringForAmount:fee]];
        prompt = [prompt stringByAppendingFormat:NSLocalizedString(@"\n         total %@ (%@)", nil),
                  [self convertToBTC:amount], [manager localCurrencyStringForAmount:amount]];
    }

    return prompt;
}

- (void)confirmRequest:(BRPaymentRequest *)request {
    if (! request.isValid) {
        if ([request.paymentAddress isValidBitcoinPrivateKey] || [request.paymentAddress isValidBitcoinBIP38Key]) {
            [self confirmSweep:request.paymentAddress];
        }
        else {
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:NSLocalizedString(@"not a valid bitcoin address", nil)
                                         message:request.paymentAddress
                                         preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction* yesButton = [UIAlertAction
                                        actionWithTitle:NSLocalizedString(@"ok", nil)
                                        style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction * action) {
                                            [alert dismissViewControllerAnimated:YES completion:nil];
                                        }];
            
            [alert addAction:yesButton];
            
            [self presentViewController:alert animated:YES completion:nil];
            
            [self cancel:nil];
        }
    }
    else if (request.r.length > 0) { // payment protocol over HTTP
        [(id)self.parentViewController.parentViewController startActivityWithTimeout:20.0];

        [BRPaymentRequest fetch:request.r timeout:20.0 completion:^(BRPaymentProtocolRequest *req, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];

                if (error && ! [request.paymentAddress isValidBitcoinAddress]) {
                    UIAlertController * alert = [UIAlertController
                                                 alertControllerWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                                 message:error.localizedDescription
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    
                    UIAlertAction* yesButton = [UIAlertAction
                                                actionWithTitle:NSLocalizedString(@"ok", nil)
                                                style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * action) {
                                                    [alert dismissViewControllerAnimated:YES completion:nil];
                                                }];
                    
                    [alert addAction:yesButton];
                    
                    [self presentViewController:alert animated:YES completion:nil];

                    [self cancel:nil];
                }
                else [self confirmProtocolRequest:(error) ? request.protocolRequest : req];
            });
        }];
    }
    else [self confirmProtocolRequest:request.protocolRequest];
}

- (void)confirmProtocolRequest:(BRPaymentProtocolRequest *)protoReq {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    BRTransaction *tx = nil;
    uint64_t amount = 0, fee = 0;
    NSString *address = [NSString addressWithScriptPubKey:protoReq.details.outputScripts.firstObject];
    BOOL valid = protoReq.isValid, outputTooSmall = NO;

    if (! valid && [protoReq.errorMessage isEqual:NSLocalizedString(@"request expired", nil)]) {
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"bad payment request", nil)
                                     message:protoReq.errorMessage
                                     preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* yesButton = [UIAlertAction
                                    actionWithTitle:NSLocalizedString(@"ok", nil)
                                    style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction * action) {
                                        [alert dismissViewControllerAnimated:YES completion:nil];
                                    }];
        
        [alert addAction:yesButton];
        
        [self presentViewController:alert animated:YES completion:nil];

        [self cancel:nil];
        return;
    }

    //TODO: check for duplicates of already paid requests

    if (self.amount == 0) {
        for (NSNumber *outputAmount in protoReq.details.outputAmounts) {
            if (outputAmount.unsignedLongLongValue > 0 && outputAmount.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) {
                outputTooSmall = YES;
            }
            amount += outputAmount.unsignedLongLongValue;
        }
    }
    else amount = self.amount;

    if ([manager.wallet containsAddress:address]) {
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:@""
                                     message:NSLocalizedString(@"this payment address is already in your wallet", nil)
                                     preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* yesButton = [UIAlertAction
                                    actionWithTitle:NSLocalizedString(@"ok", nil)
                                    style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction * action) {
                                        [alert dismissViewControllerAnimated:YES completion:nil];
                                    }];
        
        [alert addAction:yesButton];
        
        [self presentViewController:alert animated:YES completion:nil];

        [self cancel:nil];
        return;
    }
    else if (! [self.okAddress isEqual:address] && [manager.wallet addressIsUsed:address] &&
             [[UIPasteboard generalPasteboard].string isEqual:address]) {
        self.request = protoReq;
        self.okAddress = address;
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
          message:NSLocalizedString(@"\nADDRESS ALREADY USED\n\nbitcoin addresses are intended for single use only\n\n"
                                    "re-use reduces privacy for both you and the recipient and can result in loss if "
                                    "the recipient doesn't directly control the address", nil)
          delegate:self cancelButtonTitle:nil
          otherButtonTitles:NSLocalizedString(@"ignore", nil), NSLocalizedString(@"cancel", nil), nil] show];
          return;
    }
    else if (protoReq.errorMessage.length > 0 && protoReq.commonName.length > 0 &&
             ! [self.okIdentity isEqual:protoReq.commonName]) {
        self.request = protoReq;
        self.okIdentity = protoReq.commonName;
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"payee identity isn't certified", nil)
          message:protoReq.errorMessage delegate:self cancelButtonTitle:nil
          otherButtonTitles:NSLocalizedString(@"ignore", nil), NSLocalizedString(@"cancel", nil), nil] show];
        return;
    }
    else if (amount == 0 || amount == UINT64_MAX) {
        BRAmountViewController *amountController = [self.storyboard
                                                    instantiateViewControllerWithIdentifier:@"AmountViewController"];
        
        amountController.delegate = self;
        self.request = protoReq;

        if (protoReq.commonName.length > 0) {
            if (valid && ! [protoReq.pkiType isEqual:@"none"]) {
                amountController.to = [LOCK @" " stringByAppendingString:sanitizeString(protoReq.commonName)];
            }
            else if (protoReq.errorMessage.length > 0) {
                amountController.to = [REDX @" " stringByAppendingString:sanitizeString(protoReq.commonName)];
            }
            else amountController.to = sanitizeString(protoReq.commonName);
        }
        else amountController.to = address;
        
        [self.navigationController pushViewController:amountController animated:YES];
        return;
    }
    else if (amount < TX_MIN_OUTPUT_AMOUNT) {
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                     message:[NSString stringWithFormat:NSLocalizedString(@"bitcoin payments can't be less than %@", nil), [manager stringForAmount:TX_MIN_OUTPUT_AMOUNT]]
                                     preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* yesButton = [UIAlertAction
                                    actionWithTitle:NSLocalizedString(@"ok", nil)
                                    style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction * action) {
                                        [alert dismissViewControllerAnimated:YES completion:nil];
                                    }];
        
        [alert addAction:yesButton];
        
        [self presentViewController:alert animated:YES completion:nil];
        
        [self cancel:nil];
        return;
    }
    else if (outputTooSmall) {
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                     message:[NSString stringWithFormat:NSLocalizedString(@"bitcoin transaction outputs can't be less than %@", nil), [manager stringForAmount:TX_MIN_OUTPUT_AMOUNT]]
                                     preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* yesButton = [UIAlertAction
                                    actionWithTitle:NSLocalizedString(@"ok", nil)
                                    style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction * action) {
                                        [alert dismissViewControllerAnimated:YES completion:nil];
                                    }];
        
        [alert addAction:yesButton];
        
        [self presentViewController:alert animated:YES completion:nil];
        
        [self cancel:nil];
        return;
    }
    
    self.request = protoReq;
    uint64_t financial_gate_charge = [manager getFinancialGateChargeAmount:@"0.50"];
    
    tx = [manager.wallet transactionForAmounts:protoReq.details.outputAmounts
                               toOutputScripts:protoReq.details.outputScripts withFee:YES];
//    if (self.amount == 0) {
//        tx = [manager.wallet transactionForAmounts:protoReq.details.outputAmounts
//              toOutputScripts:protoReq.details.outputScripts withFee:YES];
//    }
//    else {
//        tx = [manager.wallet transactionForAmounts:@[@(self.amount),@(financial_gate_charge)]
//              toOutputScripts:@[[protoReq.details.outputScripts objectAtIndex:0], [protoReq.details.outputScripts objectAtIndex:1]] withFee:YES];
//    }
    
    if (tx) {
        amount = [manager.wallet amountSentByTransaction:tx] - [manager.wallet amountReceivedFromTransaction:tx];
        fee = [manager.wallet feeForTransaction:tx];
        
//        NSInteger i = [tx.outputAddresses indexOfObject:@"mz9N536mp3D6Ziqd2jjgPJMPcqYYrXr2Yb"];
    }
    else {
        fee = [manager.wallet feeForTxSize:[manager.wallet transactionFor:manager.wallet.balance
                                            to:address withFee:NO].size];
    }

    uint64_t prompt_fee = fee + financial_gate_charge;

    for (NSData *script in protoReq.details.outputScripts) {
        NSString *addr = [NSString addressWithScriptPubKey:script];
            
        if (! addr) addr = NSLocalizedString(@"unrecognized address", nil);
        if ([address rangeOfString:addr].location != NSNotFound) continue;
        
#if BITCOIN_TESTNET
        NSString *fixedChargeDepositAccount = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"FixedChargeDepositAccount_TEST_NET"];
#else
        NSString *fixedChargeDepositAccount = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"FixedChargeDepositAccount"];
#endif
        if ([addr isEqualToString:fixedChargeDepositAccount]) continue;
        address = [address stringByAppendingFormat:@"%@%@", (address.length > 0) ? @", " : @"", addr];
    }
    
    NSString *prompt = [self promptForAmount:amount fee:prompt_fee address:address name:protoReq.commonName
                        memo:protoReq.details.memo isSecure:(valid && ! [protoReq.pkiType isEqual:@"none"])];
    
    // to avoid the frozen pincode keyboard bug, we need to make sure we're scheduled normally on the main runloop
    // rather than a dispatch_async queue
    CFRunLoopPerformBlock([[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopCommonModes, ^{
        [self confirmTransaction:tx withPrompt:prompt forAmount:amount];
    });
}

- (void)confirmTransaction:(BRTransaction *)tx withPrompt:(NSString *)prompt forAmount:(uint64_t)amount {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    BOOL didAuth = manager.didAuthenticate;

    if (! tx) { // tx is nil if there were insufficient wallet funds
        if (! manager.didAuthenticate) [manager seedWithPrompt:prompt forAmount:amount];
        
        if (manager.didAuthenticate) {
            uint64_t fuzz = [manager amountForLocalCurrencyString:[manager localCurrencyStringForAmount:1]]*2;
            
            // if user selected an amount equal to or below wallet balance, but the fee will bring the total above the
            // balance, offer to reduce the amount to available funds minus fee
            if (self.amount <= manager.wallet.balance + fuzz && self.amount > 0) {
                int64_t amount = manager.wallet.maxOutputAmount;

                if (amount > 0 && amount < self.amount) {
                    [[[UIAlertView alloc]
                      initWithTitle:NSLocalizedString(@"insufficient funds for bitcoin network fee", nil)
                      message:[NSString stringWithFormat:NSLocalizedString(@"reduce payment amount by\n%@ (%@)?", nil),
                               [manager stringForAmount:self.amount - amount],
                               [manager localCurrencyStringForAmount:self.amount - amount]] delegate:self
                      cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                      otherButtonTitles:[NSString stringWithFormat:@"%@ (%@)",
                                         [manager stringForAmount:amount - self.amount],
                                         [manager localCurrencyStringForAmount:amount - self.amount]], nil] show];
                    self.amount = amount;
                }
                else {
                    UIAlertController * alert = [UIAlertController
                                                 alertControllerWithTitle:NSLocalizedString(@"insufficient funds for bitcoin network fee", nil)
                                                 message:nil
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    
                    UIAlertAction* yesButton = [UIAlertAction
                                                actionWithTitle:NSLocalizedString(@"ok", nil)
                                                style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * action) {
                                                    [alert dismissViewControllerAnimated:YES completion:nil];
                                                }];
                    
                    [alert addAction:yesButton];
                    
                    [self presentViewController:alert animated:YES completion:nil];
                }
            }
            else {
                UIAlertController * alert = [UIAlertController
                                             alertControllerWithTitle:NSLocalizedString(@"insufficient funds", nil)
                                             message:nil
                                             preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* yesButton = [UIAlertAction
                                            actionWithTitle:NSLocalizedString(@"ok", nil)
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * action) {
                                                [alert dismissViewControllerAnimated:YES completion:nil];
                                            }];
                
                [alert addAction:yesButton];
                
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
        else [self cancelOrChangeAmount];

        if (! didAuth) manager.didAuthenticate = NO;
        return;
    }

    if (! [manager.wallet signTransaction:tx withPrompt:prompt]) {
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                     message:NSLocalizedString(@"error signing bitcoin transaction", nil)
                                     preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* yesButton = [UIAlertAction
                                    actionWithTitle:NSLocalizedString(@"ok", nil)
                                    style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction * action) {
                                        [alert dismissViewControllerAnimated:YES completion:nil];
                                    }];
        
        [alert addAction:yesButton];
        
        [self presentViewController:alert animated:YES completion:nil];
    }

    if (! didAuth) manager.didAuthenticate = NO;

    if (! tx.isSigned) { // user canceled authentication
        [self cancelOrChangeAmount];
        return;
    }
    
    if (self.navigationController.topViewController != self.parentViewController.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }
    
    __block BOOL waiting = YES, sent = NO;
    
    [(id)self.parentViewController.parentViewController startActivityWithTimeout:30.0];
    
    [[BRPeerManager sharedInstance] publishTransaction:tx completion:^(NSError *error) {
        if (error) {
            if (! waiting && ! sent) {
                UIAlertController * alert = [UIAlertController
                                             alertControllerWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                             message:error.localizedDescription
                                             preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* yesButton = [UIAlertAction
                                            actionWithTitle:NSLocalizedString(@"ok", nil)
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * action) {
                                                [alert dismissViewControllerAnimated:YES completion:nil];
                                            }];
                
                [alert addAction:yesButton];
                
                [self presentViewController:alert animated:YES completion:nil];

                [(id)self.parentViewController.parentViewController stopActivityWithSuccess:NO];
                [self cancel:nil];
            }
        }
        else if (! sent) { //TODO: show full screen sent dialog with tx info, "you sent b10,000 to bob"
            sent = YES;
            tx.timestamp = [NSDate timeIntervalSinceReferenceDate];
            [manager.wallet registerTransaction:tx];
            [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"sent!", nil)
             center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
             popOutAfterDelay:2.0]];
            [(id)self.parentViewController.parentViewController stopActivityWithSuccess:YES];
            [(id)self.parentViewController.parentViewController ping];

            if (self.callback) {
                self.callback = [NSURL URLWithString:[self.callback.absoluteString stringByAppendingFormat:@"%@txid=%@",
                                                      (self.callback.query.length > 0) ? @"&" : @"?",
                                                      [NSString hexWithData:[NSData dataWithBytes:tx.txHash.u8
                                                                             length:sizeof(UInt256)].reverse]]];
                [[UIApplication sharedApplication] openURL:self.callback];
            }
            
            [self reset:nil];
        }
        
        waiting = NO;
    }];
    
    if (self.request.details.paymentURL.length > 0) {
        uint64_t refundAmount = 0;
        NSMutableData *refundScript = [NSMutableData data];
    
        [refundScript appendScriptPubKeyForAddress:manager.wallet.receiveAddress];
        
        for (NSNumber *amt in self.request.details.outputAmounts) {
            refundAmount += amt.unsignedLongLongValue;
        }

        // TODO: keep track of commonName/memo to associate them with outputScripts
        BRPaymentProtocolPayment *payment =
            [[BRPaymentProtocolPayment alloc] initWithMerchantData:self.request.details.merchantData
             transactions:@[tx] refundToAmounts:@[@(refundAmount)] refundToScripts:@[refundScript] memo:nil];
    
        NSLog(@"posting payment to: %@", self.request.details.paymentURL);
    
        [BRPaymentRequest postPayment:payment to:self.request.details.paymentURL timeout:20.0
        completion:^(BRPaymentProtocolACK *ack, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];
    
                if (error) {
                    if (! waiting && ! sent) {
                        UIAlertController * alert = [UIAlertController
                                                     alertControllerWithTitle:@""
                                                     message:error.localizedDescription
                                                     preferredStyle:UIAlertControllerStyleAlert];
                        
                        UIAlertAction* yesButton = [UIAlertAction
                                                    actionWithTitle:NSLocalizedString(@"ok", nil)
                                                    style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction * action) {
                                                        [alert dismissViewControllerAnimated:YES completion:nil];
                                                    }];
                        
                        [alert addAction:yesButton];
                        
                        [self presentViewController:alert animated:YES completion:nil];
                        
                        [(id)self.parentViewController.parentViewController stopActivityWithSuccess:NO];
                        [self cancel:nil];
                    }
                }
                else if (! sent) {
                    sent = YES;
                    tx.timestamp = [NSDate timeIntervalSinceReferenceDate];
                    [manager.wallet registerTransaction:tx];
                    [self.view addSubview:[[[BRBubbleView
                     viewWithText:(ack.memo.length > 0 ? ack.memo : NSLocalizedString(@"sent!", nil))
                     center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
                     popOutAfterDelay:(ack.memo.length > 0 ? 3.0 : 2.0)]];
                    [(id)self.parentViewController.parentViewController stopActivityWithSuccess:YES];
                    [(id)self.parentViewController.parentViewController ping];

                    if (self.callback) {
                        self.callback = [NSURL URLWithString:[self.callback.absoluteString
                                                              stringByAppendingFormat:@"%@txid=%@",
                                                              (self.callback.query.length > 0) ? @"&" : @"?",
                                                              [NSString hexWithData:[NSData dataWithBytes:tx.txHash.u8
                                                                                     length:sizeof(UInt256)].reverse]]];
                        [[UIApplication sharedApplication] openURL:self.callback];
                    }
                    
                    [self reset:nil];
                }

                waiting = NO;
            });
        }];
    }
    else waiting = NO;
}

- (void)confirmSweep:(NSString *)privKey {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
    if (! [privKey isValidBitcoinPrivateKey] && ! [privKey isValidBitcoinBIP38Key]) return;

    BRBubbleView *statusView = [BRBubbleView viewWithText:NSLocalizedString(@"checking private key balance...", nil)
                                center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];

    statusView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    statusView.customView = [[UIActivityIndicatorView alloc]
                             initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [(id)statusView.customView startAnimating];
    [self.view addSubview:[statusView popIn]];

    [manager sweepPrivateKey:privKey withFee:YES completion:^(BRTransaction *tx, uint64_t fee, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [statusView popOut];

            if (error) {
                UIAlertController * alert = [UIAlertController
                                             alertControllerWithTitle:@""
                                             message:error.localizedDescription
                                             preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* yesButton = [UIAlertAction
                                            actionWithTitle:NSLocalizedString(@"ok", nil)
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * action) {
                                                [alert dismissViewControllerAnimated:YES completion:nil];
                                            }];
                
                [alert addAction:yesButton];
                
                [self presentViewController:alert animated:YES completion:nil];

                [self cancel:nil];
            }
            else if (tx) {
                uint64_t amount = fee;

                for (NSNumber *amt in tx.outputAmounts) amount += amt.unsignedLongLongValue;
                self.sweepTx = tx;

                NSString *alertFmt = NSLocalizedString(@"Send %@ (%@) from this private key into your wallet? "
                                                       "The bitcoin network will receive a fee of %@ (%@).", nil);
                NSString *alertMsg = [NSString stringWithFormat:alertFmt, [manager stringForAmount:amount],
                                      [manager localCurrencyStringForAmount:amount], [manager stringForAmount:fee],
                                      [manager localCurrencyStringForAmount:fee]];
                [[[UIAlertView alloc] initWithTitle:@"" message:alertMsg delegate:self
                  cancelButtonTitle:NSLocalizedString(@"cancel", nil)
                  otherButtonTitles:[NSString stringWithFormat:@"%@ (%@)", [manager stringForAmount:amount],
                                     [manager localCurrencyStringForAmount:amount]], nil] show];
            }
            else [self cancel:nil];
        });
    }];
}

- (void)showBalance:(NSString *)address {
    if (! [address isValidBitcoinAddress]) return;

    BRWalletManager *manager = [BRWalletManager sharedInstance];
    BRBubbleView *statusView = [BRBubbleView viewWithText:NSLocalizedString(@"checking address balance...", nil)
                       center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];
    
    statusView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    statusView.customView = [[UIActivityIndicatorView alloc]
                             initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [(id)statusView.customView startAnimating];
    [self.view addSubview:[statusView popIn]];

    [manager utxosForAddresses:@[address]
    completion:^(NSArray *utxos, NSArray *amounts, NSArray *scripts, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [statusView popOut];
        
            if (error) {
                UIAlertController * alert = [UIAlertController
                                             alertControllerWithTitle:NSLocalizedString(@"couldn't check address balance", nil)
                                             message:error.localizedDescription
                                             preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* yesButton = [UIAlertAction
                                            actionWithTitle:NSLocalizedString(@"ok", nil)
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * action) {
                                                [alert dismissViewControllerAnimated:YES completion:nil];
                                            }];
                
                [alert addAction:yesButton];
                
                [self presentViewController:alert animated:YES completion:nil];
            }
            else {
                uint64_t balance = 0;
            
                for (NSNumber *amt in amounts) balance += amt.unsignedLongLongValue;
            
                NSString *alertMsg = [NSString stringWithFormat:NSLocalizedString(@"%@\n\nbalance: %@ (%@)", nil),
                                      address, [manager stringForAmount:balance],
                                      [manager localCurrencyStringForAmount:balance]];
                
                UIAlertController * alert = [UIAlertController
                                             alertControllerWithTitle:@""
                                             message:alertMsg
                                             preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* yesButton = [UIAlertAction
                                            actionWithTitle:NSLocalizedString(@"ok", nil)
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * action) {
                                                [alert dismissViewControllerAnimated:YES completion:nil];
                                            }];
                
                [alert addAction:yesButton];
                
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

- (void)cancelOrChangeAmount {
    if (self.canChangeAmount && self.request && self.amount == 0) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"change payment amount?", nil)
          message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil)
          otherButtonTitles:NSLocalizedString(@"change", nil), nil] show];
        self.amount = UINT64_MAX;
    }
    else [self cancel:nil];
}

- (void)hideTips {
    if (self.tipView.alpha > 0.5) [self.tipView popOut];
}

- (BOOL)nextTip {
    [self.clipboardText resignFirstResponder];
    if (self.tipView.alpha < 0.5) return [(id)self.parentViewController.parentViewController nextTip];

    BRBubbleView *tipView = self.tipView;

    self.tipView = nil;
    [tipView popOut];
    
    if ([tipView.text hasPrefix:SCAN_TIP]) {
        self.tipView = [BRBubbleView viewWithText:CLIPBOARD_TIP
                        tipPoint:CGPointMake(self.clipboardButton.center.x, self.clipboardButton.center.y + 10.0)
                        tipDirection:BRBubbleTipDirectionUp];
        self.tipView.backgroundColor = tipView.backgroundColor;
        self.tipView.font = tipView.font;
        self.tipView.userInteractionEnabled = NO;
    }
    else if (self.showTips && [tipView.text hasPrefix:CLIPBOARD_TIP]) {
        self.showTips = NO;
        [(id)self.parentViewController.parentViewController tip:self];
    }

    return YES;
}

- (void)resetQRGuide {
    self.scanController.message.text = nil;
    self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide"];
}

- (void)updateClipboardText {
    
    self.clipboardText.text = @"1MZnzKpNR1hALYSzm9rvKqsyDKK6qbXaf6r";
    if (check == 1) {
        BRPaymentRequest *req1;
        req1 = (_paymentRequest) ? _paymentRequest :
        [BRPaymentRequest requestWithString:[self.groupDefs stringForKey:APP_GROUP_RECEIVE_ADDRESS_KEY]];
        
        if (req1.amount == 0) {
            if (req1.isValid) {
                [self.groupDefs setObject:req1.data forKey:APP_GROUP_REQUEST_DATA_KEY];
                [self.groupDefs setObject:req1.paymentAddress forKey:APP_GROUP_RECEIVE_ADDRESS_KEY];
            }
            else {
                [self.groupDefs removeObjectForKey:APP_GROUP_REQUEST_DATA_KEY];
                [self.groupDefs removeObjectForKey:APP_GROUP_RECEIVE_ADDRESS_KEY];
            }
            
            [self.groupDefs synchronize];
        }
        self.clipboardText.text = [NSString stringWithFormat:@"Send to:\n%@\nTap to paste Bitcoin Address from clipboard",req1.paymentAddress];
        check = 0;
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *str = [[UIPasteboard generalPasteboard].string
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *text = @"";
            UIImage *img = [UIPasteboard generalPasteboard].image;
            NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
            NSCharacterSet *separators = [NSCharacterSet alphanumericCharacterSet].invertedSet;
            
            if (str) {
                [set addObject:str];
                [set addObjectsFromArray:[str componentsSeparatedByCharactersInSet:separators]];
            }
            
            if (img) {
                @synchronized ([CIContext class]) {
                    CIContext *context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@(YES)}];
                    
                    if (! context) context = [CIContext context];

                    for (CIQRCodeFeature *qr in [[CIDetector detectorOfType:CIDetectorTypeQRCode context:context
                                                  options:nil] featuresInImage:[CIImage imageWithCGImage:img.CGImage]]) {
                        [set addObject:[qr.messageString
                                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
                    }
                }
            }
        
            for (NSString *s in set) {
                BRPaymentRequest *req = [BRPaymentRequest requestWithString:s];
                
                if ([req.paymentAddress isValidBitcoinAddress]) {
                    text = (req.label.length > 0) ? sanitizeString(req.label) : req.paymentAddress;
                    break;
                }
                else if ([s hasPrefix:@"bitcoin:"]) {
                    text = sanitizeString(s);
                    break;
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                CGFloat textWidth = [text sizeWithAttributes:@{NSFontAttributeName:self.clipboardText.font}].width + 12;
        
                if (textWidth < self.clipboardButton.bounds.size.width ) textWidth = self.clipboardButton.bounds.size.width;
                if (textWidth > self.view.bounds.size.width - 16.0) textWidth = self.view.bounds.size.width - 16.0;
                self.clipboardXLeft.constant = (self.view.bounds.size.width - textWidth)/2.0;
                [self.clipboardText scrollRangeToVisible:NSMakeRange(0, 0)];
            });
        });
    }
}

- (void)payFirstFromArray:(NSArray *)array {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSUInteger i = 0;

    for (NSString *str in array) {
        BRPaymentRequest *req = [BRPaymentRequest requestWithString:str];
        NSData *data = str.hexToData.reverse;
        
        i++;
        
        // if the clipboard contains a known txHash, we know it's not a hex encoded private key
        if (data.length == sizeof(UInt256) && [manager.wallet transactionForHash:*(UInt256 *)data.bytes]) continue;
        
        if ([req.paymentAddress isValidBitcoinAddress] || [str isValidBitcoinPrivateKey] ||
            [str isValidBitcoinBIP38Key] || (req.r.length > 0 && [req.scheme isEqual:@"bitcoin"])) {
            [self performSelector:@selector(confirmRequest:) withObject:req afterDelay:0.1];// delayed to show highlight
            return;
        }
        else if (req.r.length > 0) { // may be BIP73 url: https://github.com/bitcoin/bips/blob/master/bip-0073.mediawiki
            [BRPaymentRequest fetch:req.r timeout:5.0 completion:^(BRPaymentProtocolRequest *req, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) { // don't try any more BIP73 urls
                        [self payFirstFromArray:[array objectsAtIndexes:[array
                        indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                            return (idx >= i && ([obj hasPrefix:@"bitcoin:"] || ! [NSURL URLWithString:obj]));
                        }]]];
                    }
                    else [self confirmProtocolRequest:req];
                });
            }];
            
            return;
        }
    }
    
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:@""
                                 message:NSLocalizedString(@"clipboard doesn't contain a valid bitcoin address", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* yesButton = [UIAlertAction
                                actionWithTitle:NSLocalizedString(@"ok", nil)
                                style:UIAlertActionStyleDefault
                                handler:^(UIAlertAction * action) {
                                    [alert dismissViewControllerAnimated:YES completion:nil];
                                }];
    
    [alert addAction:yesButton];
    
    [self presentViewController:alert animated:YES completion:nil];

    [self performSelector:@selector(cancel:) withObject:self afterDelay:0.1];
}

// MARK: - IBAction

- (IBAction)tip:(id)sender {
    if ([self nextTip]) return;

    if (! [sender isKindOfClass:[UIGestureRecognizer class]] || ! [[sender view] isKindOfClass:[UILabel class]]) {
        if (! [sender isKindOfClass:[UIViewController class]]) return;
        self.showTips = YES;
    }

    self.tipView = [BRBubbleView viewWithText:SCAN_TIP
                    tipPoint:CGPointMake(self.scanButton.center.x, self.scanButton.center.y - 10.0)
                    tipDirection:BRBubbleTipDirectionDown];
    self.tipView.backgroundColor = [UIColor lightGrayColor];
    self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    [self.view addSubview:[self.tipView popIn]];
}

- (IBAction)scanQR:(id)sender {
    if ([self nextTip]) return;
    [BREventManager saveEvent:@"send:scan_qr"];
    if (! [sender isEqual:self.scanButton]) self.showBalance = YES;
    [sender setEnabled:NO];
    self.scanController.delegate = self;
    self.scanController.transitioningDelegate = self;
    [self.navigationController presentViewController:self.scanController animated:YES completion:nil];
}

- (IBAction)payToClipboard:(id)sender {
    UINavigationController *sendBalanceNavController = [self.storyboard instantiateViewControllerWithIdentifier:@"SendBalanceNav"];
    ((BRSendBalanceViewController *)sendBalanceNavController.topViewController).delegate = self;
    [self.navigationController presentViewController:sendBalanceNavController animated:YES completion:nil];
    [BREventManager saveEvent:@"send_balance:send_manual"];
}

- (IBAction)reset:(id)sender {
    if (self.navigationController.topViewController != self.parentViewController.parentViewController) {
        [self.navigationController popToRootViewControllerAnimated:YES];
    }
    [BREventManager saveEvent:@"send:reset"];

    if (self.clearClipboard) [UIPasteboard generalPasteboard].string = @"";
    self.request = nil;
    [self cancel:sender];
}

- (IBAction)cancel:(id)sender {
    [BREventManager saveEvent:@"send:cancel"];
    self.url = self.callback = nil;
    self.sweepTx = nil;
    self.amount = 0;
    self.okAddress = self.okIdentity = nil;
    self.clearClipboard = self.useClipboard = NO;
    self.canChangeAmount = self.showBalance = NO;
    self.scanButton.enabled = self.clipboardButton.enabled = YES;
    [self updateClipboardText];
}

#pragma mark: - BRAmountViewControllerDelegate

- (void)amountViewController:(BRAmountViewController *)amountViewController selectedAmount:(uint64_t)amount {
    self.amount = amount;
    [self confirmProtocolRequest:self.request];
}

#pragma mark: - BRSendBalanceViewControllerDelegate

- (void)sendBalanceViewController:(BRSendBalanceViewController *)sendBalanceViewController request:(BRPaymentProtocolRequest *)request amount:(uint64_t)amount {
    self.amount = amount;
    [self confirmProtocolRequest:request];
}

- (void)sendBalanceViewController:(BRSendBalanceViewController *)sendBalanceViewController confirmRequest:(BRPaymentRequest *)request amount:(uint64_t)amount {
    self.amount = amount;
    [self confirmRequest:request];
}

#pragma mark: - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    for (AVMetadataMachineReadableCodeObject *codeObject in metadataObjects) {
        if (! [codeObject.type isEqual:AVMetadataObjectTypeQRCode]) continue;
        
        [BREventManager saveEvent:@"send:scanned_qr"];
        
        NSString *addr = [codeObject.stringValue stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BRPaymentRequest *request = [BRPaymentRequest requestWithString:addr];
        if (request.url && [BRBitID isBitIDURL:request.url]) {
            [self.scanController stop];
            [self.navigationController dismissViewControllerAnimated:YES completion:^{
                [self handleBitIDURL:request.url];
                [self resetQRGuide];
            }];
        } else if ((request.isValid && [request.scheme isEqual:@"bitcoin"]) || [addr isValidBitcoinPrivateKey] ||
                   [addr isValidBitcoinBIP38Key]) {
            self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-green"];
            [self.scanController stop];
            [BREventManager saveEvent:@"send:valid_qr_scan"];

            if (request.r.length > 0) { // start fetching payment protocol request right away
                [BRPaymentRequest fetch:request.r timeout:5.0
                completion:^(BRPaymentProtocolRequest *req, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (error) request.r = nil;
                    
                        if (error && ! request.isValid) {
                            UIAlertController * alert = [UIAlertController
                                                         alertControllerWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                                         message:error.localizedDescription
                                                         preferredStyle:UIAlertControllerStyleAlert];
                            
                            UIAlertAction* yesButton = [UIAlertAction
                                                        actionWithTitle:NSLocalizedString(@"ok", nil)
                                                        style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * action) {
                                                            [alert dismissViewControllerAnimated:YES completion:nil];
                                                        }];
                            
                            [alert addAction:yesButton];
                            
                            [self presentViewController:alert animated:YES completion:nil];

                            [self cancel:nil];
                            // continue here and handle the invalid request inside confirmRequest:
                        }

                        [self.navigationController dismissViewControllerAnimated:YES completion:^{
                            [self resetQRGuide];
                        }];
                        
                        if (error) {
                            [BREventManager saveEvent:@"send:unsuccessful_qr_payment_protocol_fetch"];
                            [self confirmRequest:request]; // payment protocol fetch failed, so use standard request
                        }
                        else {
                            [BREventManager saveEvent:@"send:successful_qr_payment_protocol_fetch"];
                            [self confirmProtocolRequest:req];
                        }
                    });
                }];
            }
            else { // standard non payment protocol request
                [self.navigationController dismissViewControllerAnimated:YES completion:^{
                    [self resetQRGuide];
                    if (request.amount > 0) self.canChangeAmount = YES;
                }];
                
                if (request.isValid && self.showBalance) {
                    [self showBalance:request.paymentAddress];
                    [self cancel:nil];
                }
                else [self confirmRequest:request];
            }
        } else {
            [BRPaymentRequest fetch:request.r timeout:5.0
            completion:^(BRPaymentProtocolRequest *req, NSError *error) { // check to see if it's a BIP73 url
                dispatch_async(dispatch_get_main_queue(), ^{
                    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetQRGuide) object:nil];
                    
                    if (req) {
                        self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-green"];
                        [self.scanController stop];
                        
                        [self.navigationController dismissViewControllerAnimated:YES completion:^{
                            [self resetQRGuide];
                        }];
                        
                        [BREventManager saveEvent:@"send:successful_bip73"];
                        [self confirmProtocolRequest:req];
                    }
                    else {
                        self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-red"];
                        
                        if (([request.scheme isEqual:@"bitcoin"] && request.paymentAddress.length > 1) ||
                            [request.paymentAddress hasPrefix:@"1"] || [request.paymentAddress hasPrefix:@"3"]) {
                            self.scanController.message.text = [NSString stringWithFormat:@"%@:\n%@",
                                                                NSLocalizedString(@"not a valid bitcoin address", nil),
                                                                request.paymentAddress];
                        }
                        else self.scanController.message.text = NSLocalizedString(@"not a bitcoin QR code", nil);
                        
                        [self performSelector:@selector(resetQRGuide) withObject:nil afterDelay:0.35];
                        [BREventManager saveEvent:@"send:unsuccessful_bip73"];
                    }
                });
            }];
        }

        break;
    }
}

#pragma mark: - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
    
    if (buttonIndex == alertView.cancelButtonIndex || [title isEqual:NSLocalizedString(@"cancel", nil)]) {
        if (self.url) {
            self.clearClipboard = YES;
            [self handleURL:self.url];
        }
        else [self cancelOrChangeAmount];
    }
    else if (self.sweepTx) {
        [(id)self.parentViewController.parentViewController startActivityWithTimeout:30];

        [[BRPeerManager sharedInstance] publishTransaction:self.sweepTx completion:^(NSError *error) {
            [(id)self.parentViewController.parentViewController stopActivityWithSuccess:(! error)];

            if (error) {
                UIAlertController * alert = [UIAlertController
                                             alertControllerWithTitle:NSLocalizedString(@"couldn't sweep balance", nil)
                                             message:error.localizedDescription
                                             preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* yesButton = [UIAlertAction
                                            actionWithTitle:NSLocalizedString(@"ok", nil)
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * action) {
                                                [alert dismissViewControllerAnimated:YES completion:nil];
                                            }];
                
                [alert addAction:yesButton];
                
                [self presentViewController:alert animated:YES completion:nil];
                
                [self cancel:nil];
                return;
            }

            [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"swept!", nil)
                                     center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)]
                                    popIn] popOutAfterDelay:2.0]];
            [self reset:nil];
        }];
    }
    else if (self.request) {
        [self confirmProtocolRequest:self.request];
    }
    else if (self.url) [self handleURL:self.url];
}

#pragma mark: - UITextViewDelegate

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView {
    if ([self nextTip]) return NO;
    return YES;
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
    //BUG: XXX this needs to take keyboard size into account
    self.useClipboard = NO;
    self.clipboardText.text = [UIPasteboard generalPasteboard].string;
    [textView scrollRangeToVisible:textView.selectedRange];
    
    [UIView animateWithDuration:0.35 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.center = CGPointMake(self.view.center.x, self.view.bounds.size.height/2.0 - 100.0);
        self.sendLabel.alpha = 0.0;
    } completion:nil];
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    [UIView animateWithDuration:0.35 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.view.center = CGPointMake(self.view.center.x, self.view.bounds.size.height/2.0);
        self.sendLabel.alpha = 1.0;
    } completion:nil];
    
    if (! self.useClipboard) [UIPasteboard generalPasteboard].string = textView.text;
    [self updateClipboardText];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if ([text isEqual:@"\n"]) {
        [textView resignFirstResponder];
        return NO;
    }
    
    if (text.length > 0 || range.length > 0) self.useClipboard = NO;
    return YES;
}

#pragma mark: - UIViewControllerAnimatedTransitioning

// This is used for percent driven interactive transitions, as well as for container controllers that have companion
// animations that might need to synchronize with the main animation.
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext {
    return 0.35;
}

// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIView *containerView = transitionContext.containerView;
    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
                     *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIImageView *img = self.scanButton.imageView;
    UIView *guide = self.scanController.cameraGuide;

    [self.scanController.view layoutIfNeeded];

    if (to == self.scanController) {
        [containerView addSubview:to.view];
        to.view.frame = from.view.frame;
        to.view.center = CGPointMake(to.view.center.x, containerView.frame.size.height*3/2);
        guide.transform = CGAffineTransformMakeScale(img.bounds.size.width/guide.bounds.size.width,
                                                     img.bounds.size.height/guide.bounds.size.height);
        guide.alpha = 0;

        [UIView animateWithDuration:0.1 animations:^{
            img.alpha = 0.0;
            guide.alpha = 1.0;
        }];

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            to.view.center = from.view.center;
        } completion:^(BOOL finished) {
            img.alpha = 1.0;
            [transitionContext completeTransition:YES];
        }];

        [UIView animateWithDuration:0.8 delay:0.15 usingSpringWithDamping:0.5 initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseOut animations:^{
            guide.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            [to.view addSubview:guide];
        }];
    }
    else {
        [containerView insertSubview:to.view belowSubview:from.view];
        [self cancel:nil];

        [UIView animateWithDuration:0.8 delay:0.0 usingSpringWithDamping:0.5 initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseIn animations:^{
            guide.transform = CGAffineTransformMakeScale(img.bounds.size.width/guide.bounds.size.width,
                                                         img.bounds.size.height/guide.bounds.size.height);
            guide.alpha = 0.0;
        } completion:^(BOOL finished) {
            guide.transform = CGAffineTransformIdentity;
            guide.alpha = 1.0;
        }];

        [UIView animateWithDuration:[self transitionDuration:transitionContext] - 0.15 delay:0.15
        options:UIViewAnimationOptionCurveEaseIn animations:^{
            from.view.center = CGPointMake(from.view.center.x, containerView.frame.size.height*3/2);
        } completion:^(BOOL finished) {
            [transitionContext completeTransition:YES];
        }];
    }
}

#pragma mark: - UIViewControllerTransitioningDelegate

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source {
    return self;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    return self;
}

#pragma mark: - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];
    
    //TODO: allow user to create a payment protocol request object, and use merge avoidance techniques:
    // https://medium.com/@octskyward/merge-avoidance-7f95a386692f
    
    if ([title isEqual:NSLocalizedString(@"copy address to clipboard", nil)] ||
        [title isEqual:NSLocalizedString(@"copy request to clipboard", nil)]) {
        [UIPasteboard generalPasteboard].string = (self.paymentRequest.amount > 0) ? self.paymentRequest.string :
        self.paymentAddress;
        NSLog(@"\n\nCOPIED PAYMENT REQUEST/ADDRESS:\n\n%@", [UIPasteboard generalPasteboard].string);
        
        [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"copied", nil)
                                                    center:CGPointMake(self.view.bounds.size.width/2.0, self.view.bounds.size.height/2.0 - 130.0)] popIn]
                               popOutAfterDelay:2.0]];
        [BREventManager saveEvent:@"receive:copy_address"];
    }
    else if ([title isEqual:NSLocalizedString(@"send address as email", nil)] ||
             [title isEqual:NSLocalizedString(@"send request as email", nil)]) {
        //TODO: implement BIP71 payment protocol mime attachement
        // https://github.com/bitcoin/bips/blob/master/bip-0071.mediawiki
        
        if ([MFMailComposeViewController canSendMail]) {
            MFMailComposeViewController *composeController = [MFMailComposeViewController new];
            
            composeController.subject = NSLocalizedString(@"Bitcoin address", nil);
            [composeController setMessageBody:self.paymentRequest.string isHTML:NO];
            [composeController addAttachmentData:UIImagePNGRepresentation(self.qrView.image) mimeType:@"image/png"
                                        fileName:@"qr.png"];
            composeController.mailComposeDelegate = self;
            [self.navigationController presentViewController:composeController animated:YES completion:nil];
            composeController.view.backgroundColor =
            [UIColor colorWithPatternImage:[UIImage imageNamed:@"wallpaper-default"]];
            [BREventManager saveEvent:@"receive:send_email"];
        }
        else {
            [BREventManager saveEvent:@"receive:email_not_configured"];
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:@""
                                         message:NSLocalizedString(@"email not configured", nil)
                                         preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction* yesButton = [UIAlertAction
                                        actionWithTitle:NSLocalizedString(@"ok", nil)
                                        style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction * action) {
                                            [alert dismissViewControllerAnimated:YES completion:nil];
                                        }];
            
            [alert addAction:yesButton];
            
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    else if ([title isEqual:NSLocalizedString(@"send address as message", nil)] ||
             [title isEqual:NSLocalizedString(@"send request as message", nil)]) {
        if ([MFMessageComposeViewController canSendText]) {
            MFMessageComposeViewController *composeController = [MFMessageComposeViewController new];
            
            if ([MFMessageComposeViewController canSendSubject]) {
                composeController.subject = NSLocalizedString(@"Bitcoin address", nil);
            }
            
            composeController.body = self.paymentRequest.string;
            
            if ([MFMessageComposeViewController canSendAttachments]) {
                [composeController addAttachmentData:UIImagePNGRepresentation(self.qrView.image)
                                      typeIdentifier:(NSString *)kUTTypePNG filename:@"qr.png"];
            }
            
            composeController.messageComposeDelegate = self;
            [self.navigationController presentViewController:composeController animated:YES completion:nil];
            composeController.view.backgroundColor = [UIColor colorWithPatternImage:
                                                      [UIImage imageNamed:@"wallpaper-default"]];
            [BREventManager saveEvent:@"receive:send_message"];
        }
        else {
            [BREventManager saveEvent:@"receive:message_not_configured"];
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:@""
                                         message:NSLocalizedString(@"sms not currently available", nil)
                                         preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction* yesButton = [UIAlertAction
                                        actionWithTitle:NSLocalizedString(@"ok", nil)
                                        style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction * action) {
                                            [alert dismissViewControllerAnimated:YES completion:nil];
                                        }];
            
            [alert addAction:yesButton];
            
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    else if ([title isEqual:NSLocalizedString(@"request an amount", nil)]) {
        UINavigationController *amountNavController = [self.storyboard
                                                       instantiateViewControllerWithIdentifier:@"AmountNav"];
        
        ((BRAmountViewController *)amountNavController.topViewController).delegate = self;
        [self.navigationController presentViewController:amountNavController animated:YES completion:nil];
        [BREventManager saveEvent:@"receive:request_amount"];
    }
}

- (BRPaymentRequest *)paymentRequest {
    if (_paymentRequest) return _paymentRequest;
    return [BRPaymentRequest requestWithString:self.paymentAddress];
}

- (NSString *)paymentAddress {
    if (_paymentRequest) return _paymentRequest.paymentAddress;
    return [BRWalletManager sharedInstance].wallet.receiveAddress;
}

#pragma mark: - MFMessageComposeViewControllerDelegate

- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
                 didFinishWithResult:(MessageComposeResult)result {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark: - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end
